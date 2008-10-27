require 'optparse'
require 'cucumber'

module Cucumber
  class CLI
    class << self
      attr_writer :step_mother, :executor, :features
    
      def execute
        @execute_called = true
        parse(ARGV).execute!(@step_mother, @executor, @features)
      end
      
      def execute_called?
        @execute_called
      end

      def parse(args)
        cli = new
        cli.parse_options!(args)
        cli
      end
    end
    
    attr_reader :options
    FORMATS = %w{pretty profile progress html doc}
    DEFAULT_FORMAT = 'pretty'
    
    def initialize
      @paths = []
      @options = { 
        :require => nil, 
        :lang    => 'en', 
        :dry_run => false, 
        :source  => true,
        :formats => {},
        :excludes => []
      }
      @active_format = DEFAULT_FORMAT
    end

    def parse_options!(args)
      return parse_args_from_profile('default') if args.empty?
      args.extend(OptionParser::Arguable)

      args.options do |opts|
        opts.banner = "Usage: cucumber [options] FILES|DIRS"
        opts.on("-r LIBRARY|DIR", "--require LIBRARY|DIR", "Require files before executing the features.",
          "If this option is not specified, all *.rb files that",
          "are siblings or below the features will be autorequired") do |v|
          @options[:require] ||= []
          @options[:require] << v
        end
        opts.on("-l LINE", "--line LINE", "Only execute the scenario at the given line") do |v|
          @options[:line] = v
        end
        opts.on("-a LANG", "--language LANG", "Specify language for features (Default: #{@options[:lang]})",
          "Available languages: #{Cucumber.languages.join(", ")}",
          "Look at #{Cucumber::LANGUAGE_FILE} for keywords") do |v|
          @options[:lang] = v
        end
        opts.on("-f FORMAT", "--format FORMAT", "How to format features (Default: #{DEFAULT_FORMAT})",
          "Available formats: #{FORMATS.join(", ")}") do |v|
          unless FORMATS.index(v) 
            STDERR.puts "Invalid format: #{v}\n"
            STDERR.puts opts.help
            exit 1
          end
          @options[:formats][v] ||= []
          @options[:formats][v] << STDOUT
          @active_format = v
        end
        opts.on("--exclude=PATTERN", "Don't run features matching a pattern") do |v|
          @options[:excludes] << v
        end
        opts.on("-p=PROFILE", "--profile=PROFILE", "Pull commandline arguments from cucumber.yml.") do |v|
          parse_args_from_profile(v)
        end
        opts.on("-d", "--dry-run", "Invokes formatters without executing the steps.") do
          @options[:dry_run] = true
        end
        opts.on("-n", "--no-source", "Don't show the file and line of the step definition with the steps.") do
          @options[:source] = false
        end
        opts.on("-o", "--out=FILE", "Write output to a file instead of STDOUT.") do |v|
          @options[:formats][@active_format] ||= []
          if @options[:formats][@active_format].last == STDOUT
            @options[:formats][@active_format][-1] = File.open(v, 'w')
          else
            @options[:formats][@active_format] << File.open(v, 'w')
          end
        end
        opts.on_tail("--version", "Show version") do
          puts VERSION::STRING
          exit
        end
        opts.on_tail("--help", "You're looking at it") do
          puts opts.help
          exit
        end
      end.parse!
      
      if @options[:formats].empty?
        @options[:formats][DEFAULT_FORMAT] = [STDOUT]
      end
            
      # Whatever is left after option parsing is the FILE arguments
      @paths += args
    end
    
    def parse_args_from_profile(profile)
      return unless File.exist?('cucumber.yml')
      require 'yaml'
      cucumber_yml = YAML::load(IO.read('cucumber.yml'))
      args_from_yml = cucumber_yml[profile]
      raise "Expected to find a String, got #{args_from_yml.inspect}. cucumber.yml:\n#{cucumber_yml}" unless String === args_from_yml
      parse_options!(args_from_yml.split(' '))
    end
    
    def execute!(step_mother, executor, features)
      Cucumber.load_language(@options[:lang])
      executor.formatters = build_formatter_broadcaster(step_mother)
      require_files
      load_plain_text_features(features)
      executor.line = @options[:line].to_i if @options[:line]
      executor.visit_features(features)
      exit 1 if executor.failed
    end
    
  private
    
    # Requires files - typically step files and ruby feature files.
    def require_files
      ARGV.clear # Shut up RSpec
      require "cucumber/treetop_parser/feature_#{@options[:lang]}"
      require "cucumber/treetop_parser/feature_parser"

      requires = @options[:require] || feature_dirs
      libs = requires.map do |path|
        path = path.gsub(/\\/, '/') # In case we're on windows. Globs don't work with backslashes.
        File.directory?(path) ? Dir["#{path}/**/*.rb"] : path
      end.flatten.uniq
      libs.each do |lib|
        begin
          require lib
        rescue LoadError => e
          e.message << "\nFailed to load #{lib}"
          raise e
        end
      end
    end

    def feature_files
      potential_feature_files = @paths.map do |path|
        path = path.gsub(/\\/, '/') # In case we're on windows. Globs don't work with backslashes.
        File.directory?(path) ? Dir["#{path}/**/*.feature"] : path
      end.flatten.uniq
      
      @options[:excludes].each do |exclude|
        potential_feature_files.reject! do |path|
          path =~ /#{Regexp.escape(exclude)}/
        end
      end
      
      potential_feature_files
    end
    
    def feature_dirs
      feature_files.map{|f| File.directory?(f) ? f : File.dirname(f)}.uniq
    end
    
    def load_plain_text_features(features)
      parser = TreetopParser::FeatureParser.new

      feature_files.each do |f|
        features << parser.parse_feature(f)
      end
    end
    
    def build_formatter_broadcaster(step_mother)
      formatter_broadcaster = Broadcaster.new
      @options[:formats].each do |format, output_list|
        output_broadcaster = build_output_broadcaster(output_list)
        case format
        when 'pretty'
          formatter_broadcaster.register(Formatters::PrettyFormatter.new(output_broadcaster, step_mother, @options))
        when 'progress'
          formatter_broadcaster.register(Formatters::ProgressFormatter.new(output_broadcaster))
        when 'profile'
          formatter_broadcaster.register(Formatters::ProfileFormatter.new(output_broadcaster, step_mother))
        when 'html'
          formatter_broadcaster.register(Formatters::HtmlFormatter.new(output_broadcaster, step_mother))
        when 'doc'
          formatter_broadcaster.register(Formatters::DocFormatter.new(output_broadcaster, step_mother))
        else
          raise "Unknown formatter: #{@options[:format]}"
        end
      end
      formatter_broadcaster
    end

    def build_output_broadcaster(output_list)
      output_broadcaster = Broadcaster.new
      output_list.each do |output|
        output_broadcaster.register(output)
      end
      output_broadcaster
    end
        
  end
end

extend Cucumber::StepMethods
Cucumber::CLI.step_mother = step_mother
Cucumber::CLI.executor = executor

extend Cucumber::Tree
Cucumber::CLI.features = features

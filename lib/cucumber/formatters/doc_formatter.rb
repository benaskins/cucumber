module Cucumber
  module Formatters
    class DocFormatter
      def initialize(io, step_mother)
        @io = io
        @step_mother = step_mother
        @errors = []
        @scenario_table_header = []
      end

      def visit_features(features)
        @io.puts(<<-HTML)
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html 
  PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
  <head>
    <title>#{Cucumber.language['feature']}</title>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
    <meta http-equiv="Expires" content="-1" />
    <meta http-equiv="Pragma" content="no-cache" />
    <style>
#{IO.read(File.dirname(__FILE__) + '/doc.css')}
    </style>
  </head>
  <body>
HTML
      end
      
    
      def visit_feature(feature)
        @io.puts %{      <div class="story">}
        feature.accept(self)
        @io.puts %{      </div>}
      end
      
      def visit_header(header)
        header = header.split(/\n/)
        @io.puts %{        <h1>#{header[0]}</h1>}
        @io.puts %{        <p><em>#{header[1..-1].join("<br />\n")}}
        @io.puts %{        </em></p>}
      end

      def visit_regular_scenario(scenario)
        @scenario_table_header = scenario.table_header
        if @insublist
          @insublist = false
          @io.puts %{ </ul> }
        end
        @io.puts %{         <h3>#{Cucumber.language['scenario']}: #{scenario.name}</h3>}
        @io.puts %{          <ul>}
        scenario.accept(self)
        @io.puts %{          </ul>}
      end

      def visit_row_scenario(scenario)
        # @io.puts %{         <h3>#{Cucumber.language['scenario']}: #{scenario.name}</h3>}
        # @io.puts %{          <h4>}
        # @io.puts @scenario_table_header.join(", ")
        # @io.puts %{          </h4>}
        # @io.puts %{          <ul>}
        # scenario.accept(self)
        # @io.puts %{          </ul>}
      end

      def visit_row_step(step)
        _, args, _ = step.regexp_args_proc(@step_mother)
        args.each do |arg|
          @io.puts %{ <li id="#{step.id}"><span>#{arg}</span></li>}
        end
      end

      def visit_regular_step(step)
        regexp, _, _ = step.regexp_args_proc(@step_mother)
        if step.keyword != "And" && @insublist
          @insublist = false
          @io.puts %{ </ul> }
        end
        if step.keyword == "And" && !@insublist
          @insublist = true
          @io.puts %{ <ul> }
        end
        @io.puts %{ <li id="#{step.id}">#{step.keyword} #{step.format(regexp, '<span>%s</span>')}</li>}
      end
      
      def step_passed(step, regexp, args)
        print_javascript_tag("stepPassed(#{step.id})")
      end
      
      def step_failed(step, regexp, args)
        @errors << step.error
        print_javascript_tag("stepFailed(#{step.id}, #{step.error.message.inspect}, #{step.error.backtrace.join("\n").inspect})")
      end
      
      def step_pending(step, regexp, args)
        # print_javascript_tag("stepPending(#{step.id})")
      end
      
      def step_skipped(step, regexp, args)
        # noop
      end

      def print_javascript_tag(js)
        @io.puts %{    <script type="text/javascript">#{js}</script>}
      end

      def dump
        @io.puts <<-HTML
  </body>
</html>
HTML
      end
    end
  end
end

# coding: utf-8

require 'transpec/base_rewriter'
require 'transpec/util'
require 'transpec/ast/scanner'

module Transpec
  class DynamicAnalyzer
    class Rewriter < BaseRewriter
      include Util

      def process(ast, source_rewriter)
        # TODO: Currently multitheading is not considered...
        clear_requests!
        collect_requests(ast)
        process_requests(source_rewriter)
      end

      def requests
        @requests ||= {}
      end

      def clear_requests!
        @requests = nil
      end

      def register_request(node, key, instance_eval_string)
        if requests.key?(node)
          requests[node][key] = instance_eval_string
        else
          requests[node] = { key => instance_eval_string }
        end
      end

      private

      def collect_requests(ast)
        AST::Scanner.scan(ast) do |node, ancestor_nodes|
          Syntax.standalone_syntaxes.each do |syntax_class|
            syntax_class.register_request_for_dynamic_analysis(node, self)
            next unless syntax_class.target_node?(node)
            syntax = syntax_class.new(node, ancestor_nodes)
            syntax.register_request_for_dynamic_analysis(self)
          end
        end
      end

      def process_requests(source_rewriter)
        requests.each do |node, analysis_codes|
          inject_analysis_method(node, analysis_codes, source_rewriter)
        end
      end

      def inject_analysis_method(node, analysis_codes, source_rewriter)
        source_range = node.loc.expression

        front = "#{ANALYSIS_METHOD}("
        rear = format(
          ', %s, self, __FILE__, %d, %d)',
          hash_literal(analysis_codes), source_range.begin_pos, source_range.end_pos
        )

        if contain_here_document?(node)
          front << '('
          rear = "\n" + indentation_of_line(node.loc.expression.end) + ')' + rear
        end

        source_rewriter.insert_before(source_range, front)
        source_rewriter.insert_after(source_range, rear)
      rescue OverlappedRewriteError # rubocop:disable HandleExceptions
      end

      # Hash#inspect generates invalid literal with following example:
      #
      # > eval({ :predicate? => 1 }.inspect)
      # SyntaxError: (eval):1: syntax error, unexpected =>
      # {:predicate?=>1}
      #               ^
      def hash_literal(hash)
        literal = '{ '

        hash.each_with_index do |(key, value), index|
          literal << ', ' unless index == 0
          literal << "#{key.inspect} => #{value.inspect}"
        end

        literal << ' }'
      end
    end
  end
end
# class Redis
#   def call
#     "I do fun stuff"
#   end
# end
#
# require 'opentelemetry-instrumentation-redis'
# OpenTelemetry::Instrumentation::Redis::Instrumentation.install

module ScoutApm
  module Instruments
    module RedisClientMonkey
      def call(*args, &block)
        command = args.first.first rescue "Unknown"

        self.class.instrument("Redis", command) do
          super(*args, &block)
        end
      end
    end

    class Redis
      attr_reader :context

      def initialize(context)
        @context = context
        @installed = false
      end

      def logger
        context.logger
      end

      def installed?
        @installed
      end

      def install
        if defined?(::Redis) && defined?(::Redis::Client)
          @installed = true

          logger.info "Instrumenting Redis"

          ::Redis::Client.class_eval do
            include ScoutApm::Tracer
          end

          ::Redis::Client.prepend(RedisClientMonkey)
        end
      end
    end
  end
end

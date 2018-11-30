module ScoutApm
  module Instruments
    # instrumentation for Rails 3, 4, and 5 is the same.
    class ActionControllerRails3Rails4
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
        # We previously instrumented ActionController::Metal, which missed
        # before and after filter timing. Instrumenting Base includes those
        # filters, at the expense of missing out on controllers that don't use
        # the full Rails stack.
        if defined?(::ActionController)
          @installed = true

          if defined?(::ActionController::Base)
            logger.info "Instrumenting ActionController::Base"
            ::ActionController::Base.class_eval do
              # include ScoutApm::Tracer
              include ScoutApm::Instruments::ActionControllerBaseInstruments
            end
          end

          if defined?(::ActionController::Metal)
            logger.info "Instrumenting ActionController::Metal"
            ::ActionController::Metal.class_eval do
              include ScoutApm::Instruments::ActionControllerMetalInstruments
            end
          end

          if defined?(::ActionController::API)
            logger.info "Instrumenting ActionController::Api"
            ::ActionController::API.class_eval do
              include ScoutApm::Instruments::ActionControllerAPIInstruments
            end
          end
        end

      end

      # Returns a new anonymous module each time it is called. So
      # we can insert this multiple times into the ancestors
      # stack. Otherwise it only exists the first time you include it
      # (under Metal, instead of under API) and we miss instrumenting
      # before_action callbacks
      def self.build_instrument_module
        Module.new do
          def process_action(*args)
            req = ScoutApm::RequestManager.lookup
            current_layer = req.current_layer
            agent_context = ScoutApm::Agent.instance.context

            # Check if this this request is to be reported instantly
            if instant_key = request.cookies['scoutapminstant']
              agent_context.logger.info "Instant trace request with key=#{instant_key} for path=#{path}"
              req.instant_key = instant_key
            end

            if current_layer && current_layer.type == "Controller"
              # Don't start a new layer if ActionController::API or ActionController::Base handled it already.
              super
            else
              req.annotate_request(:uri => ScoutApm::Instruments::ActionControllerRails3Rails4.scout_transaction_uri(request))

              # IP Spoofing Protection can throw an exception, just move on w/o remote ip
              if agent_context.config.value('collect_remote_ip')
                req.context.add_user(:ip => request.remote_ip) rescue nil
              end
              req.set_headers(request.headers)

              resolved_name = scout_action_name(*args)
              layer = ScoutApm::Layer.new("Controller", "#{controller_path}/#{resolved_name}")

              if enable_scoutprof? && ScoutApm::Agent.instance.context.config.value('profile') && ScoutApm::Instruments::Stacks::ENABLED
                if defined?(ScoutApm::Instruments::Stacks::INSTALLED) && ScoutApm::Instruments::Stacks::INSTALLED
                  # Capture ScoutProf if we can
                  req.enable_profiled_thread!
                  layer.set_root_class(self.class)
                  layer.traced!
                end
              end

              req.start_layer(layer)
              begin
                super
              rescue
                req.error!
                raise
              ensure
                req.stop_layer
              end
            end
          end
        end
      end

      # Given an +ActionDispatch::Request+, formats the uri based on config settings.
      # XXX: Don't lookup context like this - find a way to pass it through
      def self.scout_transaction_uri(request, config=ScoutApm::Agent.instance.context.config)
        case config.value("uri_reporting")
        when 'path'
          request.path # strips off the query string for more security
        else # default handles filtered params
          request.filtered_path
        end
      end
    end

    module ActionControllerBaseInstruments
      include ScoutApm::Instruments::ActionControllerRails3Rails4.build_instrument_module

      def scout_action_name(*args)
        action_name
      end

      def enable_scoutprof?
        true
      end
    end

    module ActionControllerMetalInstruments
      include ScoutApm::Instruments::ActionControllerRails3Rails4.build_instrument_module

      def scout_action_name(*args)
        action_name = args[0]
      end

      def enable_scoutprof?
        false
      end
    end

    module ActionControllerAPIInstruments
      include ScoutApm::Instruments::ActionControllerRails3Rails4.build_instrument_module

      def scout_action_name(*args)
        action_name
      end

      def enable_scoutprof?
        false
      end
    end

    # Empty, noop module to provide compatibility w/ previous manual instrumentation
    module ActionControllerRails3Rails4Instruments
    end
  end
end


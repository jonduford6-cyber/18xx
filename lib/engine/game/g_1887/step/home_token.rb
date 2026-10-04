# frozen_string_literal: true

require_relative '../../../step/home_token'

module Engine
  module Game
    module G1887
      module Step
        # Part B: a restarted Railway's president chooses its home station
        # when it floats (the standard home-token step and map clicks); the
        # chosen city then counts as its home
        class HomeToken < Engine::Step::HomeToken
          def process_place_token(action)
            corporation = pending_entity
            super
            corporation.coordinates ||= action.city.hex.id
          end
        end
      end
    end
  end
end

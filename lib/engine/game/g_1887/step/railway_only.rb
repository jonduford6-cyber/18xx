# frozen_string_literal: true

require_relative '../../../step/bankrupt'
require_relative '../../../step/buy_company'
require_relative '../../../step/buy_train'
require_relative '../../../step/discard_train'
require_relative '../../../step/dividend'
require_relative '../../../step/exchange'
require_relative '../../../step/route'
require_relative '../../../step/special_track'
require_relative '../../../step/token'
require_relative '../../../step/track'

module Engine
  module Game
    module G1887
      module Step
        # The standard operating steps, inactive (so skipped silently)
        # while a Finance House or Construction Company operates.
        module RailwayOnly
          def active?
            !@game.financial?(current_entity) && super
          end
        end

        %i[Bankrupt BuyCompany DiscardTrain Exchange
           Route SpecialTrack Token Track].each do |name|
          const_set(name, Class.new(Engine::Step.const_get(name)) { include RailwayOnly })
        end
      end
    end
  end
end

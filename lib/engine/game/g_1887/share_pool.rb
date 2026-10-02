# frozen_string_literal: true

require_relative '../../share_pool'

module Engine
  module Game
    module G1887
      class SharePool < Engine::SharePool
        # Log sales as a percentage ("sells 30% of BAGS"), never as a
        # number of share units (a unit is 20% for Finance Houses and
        # Construction Companies, but 10% for Railways).
        def num_presentation(bundle)
          return super if bundle.num_shares == 1

          "#{bundle.percent}%"
        end
      end
    end
  end
end

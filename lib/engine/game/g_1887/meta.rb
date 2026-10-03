# frozen_string_literal: true

require_relative '../meta'

module Engine
  module Game
    module G1887
      module Meta
        include Game::Meta

        DEV_STAGE = :prealpha

        GAME_DESIGNER = 'Jon'
        GAME_LOCATION = 'Argentina'

        PLAYER_RANGE = [3, 4].freeze

        OPTIONAL_RULES = [
          {
            sym: :two_six_trains,
            short_name: 'Two 6-trains',
            desc: 'Only two 6-trains are available instead of three.',
          },
          {
            sym: :no_bank_pool_limit,
            short_name: 'No bank pool limit',
            desc: 'Sales, Issues and Reissues may put any share of a company into the bank pool, not only up to 50%.',
          },
        ].freeze
      end
    end
  end
end

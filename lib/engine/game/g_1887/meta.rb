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
        # the rulebook, served by the site from public/rules (a relative path: it works on every host)
        GAME_RULES_URL = 'https://1887game.com/rules/1887_rules.pdf'

        PLAYER_RANGE = [2, 4].freeze

        OPTIONAL_RULES = [
          {
            sym: :two_six_trains,
            short_name: 'Two 6-trains',
            desc: 'Only two 6-trains are available instead of three.',
          },
          {
            sym: :no_bank_pool_limit,
            short_name: 'No bank pool limit',
            desc: 'Sales and Issues may put any share of a company into the bank pool, not only up to 50%.',
          },
          {
            sym: :contested_merger,
            short_name: 'Contested merger',
            desc: 'Mergers are proposed in a Merger Round after each Operating Round set and decided by a vote of the ' \
                  'shareholders, instead of the friendly merger. Not with Purchase of control. With two players the friendly merger is used.',
          },
          {
            sym: :purchase_of_control,
            short_name: 'Purchase of control',
            desc: 'Mergers are announced in a Merger Round after each Operating Round set and decided by an auction for ' \
                  'control, instead of the friendly merger. Not with Contested merger.',
          },
          {
            sym: :permanent_five_trains,
            short_name: 'Permanent 5-trains',
            desc: '5-trains never rust; 6-trains rust 3-trains; Diesels rust 4-trains',
          },
          {
            sym: :four_four_trains,
            short_name: 'Four 4-trains',
            desc: 'There are four 4-trains instead of three.',
          },
          {
            sym: :higher_revenues,
            short_name: 'Higher revenues',
            desc: 'Every stop a train counts is worth $10 more, off-boards included.',
          },
          {
            sym: :two_player_retired_chain,
            short_name: 'Two players: third chain retired (prototype)',
            desc: 'With two players, only two Charters are auctioned; the third Finance House starts retired and may be ' \
                  'started later. Ignored with three or four players.',
          },
          {
            sym: :legacy_emergency_issue,
            short_name: 'Legacy emergency issue',
            desc: 'In an emergency train purchase, corporations may issue shares to raise money (the old rule). ' \
                  'Without this option nobody issues shares in an emergency.',
          },
          {
            sym: :legacy_purchase_of_control,
            short_name: 'Legacy purchase of control',
            desc: 'The purchase of control as it worked before the buyout rule: the holders are paid and keep half their ' \
                  "shares, and the winner receives the missing president's certificate from the unissued shares. For games " \
                  'started under the old rule. It does nothing without the purchase of control.',
          },
          {
            sym: :strict_home_city,
            short_name: 'Strict home city',
            desc: "A restarted Railway's home city must have a continuous path of track to Buenos Aires that does not pass " \
                  'through a city filled by other Railways\' tokens, an off board location or the ferry hexes.',
          },
        ].freeze

        # At most one merger style (the site's creation form unticks the other)
        MUTEX_RULES = [%i[contested_merger purchase_of_control]].freeze
      end
    end
  end
end

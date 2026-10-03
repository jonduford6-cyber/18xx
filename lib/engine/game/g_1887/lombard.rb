# frozen_string_literal: true

require_relative '../../minor'
require_relative '../../share_holder'

module Engine
  module Game
    module G1887
      # Lombard Street (sections 3, 10.1, 10.6): a holder of certificates and
      # cash with its own treasury, owned and acted for by the buyer of the
      # Lombard Street private. A minor that can hold shares (as 1880's);
      # it never floats, so it never takes an operating turn.
      class Lombard < Engine::Minor
        include ShareHolder

        LOGO = 'data:image/svg+xml;charset=utf-8,' \
               "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 50 50'>" \
               "<circle cx='25' cy='25' r='24' fill='%231f3a5f'/>" \
               "<text x='25' y='32' font-size='19' text-anchor='middle' fill='white' " \
               "font-family='Arial'>LS</text></svg>"

        def num_shares_of(corporation, ceil: true)
          num = percent_of(corporation).to_f / corporation.share_percent
          ceil ? num.ceil : num
        end

        # Its holdings, for the card (it has no certificates of its own)
        def corporate_shares
          shares
        end

        def reserved_shares
          []
        end

        def hide_shares?
          true
        end

        def logo
          LOGO
        end

        def simple_logo
          LOGO
        end
      end
    end
  end
end

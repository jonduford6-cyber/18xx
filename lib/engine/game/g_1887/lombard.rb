# frozen_string_literal: true

require_relative '../../minor'
require_relative '../../share_holder'

module Engine
  module Game
    module G1887
      # Lombard Street (sections 3, 10.1, 10.6): a holder of certificates and
      # cash with its own treasury, owned and acted for by the buyer of the
      # Lombard Street private. A minor that can hold shares (as 1880's);
      # it never floats, so it never takes an operating turn. Named Minor (as
      # 1880's) so saved actions record its type as 'minor'.
      class Minor < Engine::Minor
        include ShareHolder

        # A logo served by the site (its content security policy blocks the
        # data: images the first version used): the round 'LS' badge
        LOGO = '/logos/1807/LS.svg'

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

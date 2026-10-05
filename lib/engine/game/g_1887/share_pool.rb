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

        # 5.5: a Treasury certificate is paid for at the market price and
        # the money goes into that company's Treasury. BAGS and BAWR have
        # full capitalization, so the shared pool would send it to the bank.
        def transfer_shares(bundle, to_entity, **kwargs)
          corporation = bundle.corporation
          if bundle.owner == corporation && to_entity != corporation && kwargs[:receiver] == @bank &&
             kwargs[:price].to_i.positive?
            kwargs = kwargs.merge(receiver: corporation)
          end
          super(bundle, to_entity, **kwargs)
        end
      end
    end
  end
end

# frozen_string_literal: true

require_relative '../../../step/base'
require_relative 'railway_only'

module Engine
  module Game
    module G1887
      module Step
        # 11.3.5: at the start of a Railway's turn, before track, its
        # president may Issue one certificate from its treasury or Redeem one
        # from the bank pool (not both, once), or skip. Buttons, as for Buy.
        class IssueRedeem < Engine::Step::Base
          include RailwayOnly

          ACTIONS = %w[choose pass].freeze

          def actions(entity)
            return [] unless entity == current_entity
            return [] if choices.empty?

            ACTIONS
          end

          def description
            'Issue or Redeem'
          end

          # Nothing to issue or redeem: no log line on every Railway turn
          def log_skip(_entity); end

          def pass_description
            'Skip (Issue/Redeem)'
          end

          def choice_name
            "#{current_entity.name}: Issue or Redeem one certificate (once, before track)"
          end

          def choices
            corporation = current_entity
            list = {}
            if (share = @game.issuable_share(corporation))
              list['issue'] = "Issue #{share.percent}% Treasury Share (#{price_str(corporation, share)})"
            end
            if (share = @game.redeemable_share(corporation))
              list['redeem'] = "Redeem #{share.percent}% Market Share (#{price_str(corporation, share)})"
            end
            list
          end

          def process_choose(action)
            corporation = action.entity
            case action.choice
            when 'issue'
              share = @game.issuable_share(corporation)
              raise GameError, "#{corporation.name} cannot issue a certificate" unless share

              @game.issue_shares(corporation, [share])
            when 'redeem'
              share = @game.redeemable_share(corporation)
              raise GameError, "#{corporation.name} cannot redeem a certificate" unless share

              @game.redeem_share(corporation, share)
            else
              raise GameError, "Unknown choice #{action.choice}"
            end
            pass!
          end

          private

          def price_str(corporation, share)
            @game.format_currency(corporation.share_price.price * share.num_shares)
          end
        end
      end
    end
  end
end

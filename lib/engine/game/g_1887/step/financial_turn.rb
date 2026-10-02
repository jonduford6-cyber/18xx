# frozen_string_literal: true

require_relative '../../../step/base'
require_relative '../../../step/auctioner'

module Engine
  module Game
    module G1887
      module Step
        # The operating turn of a Finance House or Construction Company.
        # A Finance House may start a Construction Company (11.3.3) or
        # pass; the other financial actions are not built yet.
        #
        # Start is offered as a 'bid' (the amount paid), which makes the
        # site show its auction screen: the startable companies as cards,
        # and an amount box for the selected one.
        class FinancialTurn < Engine::Step::Base
          include Engine::Step::Auctioner

          START_MIN = 120

          def actions(entity)
            return [] unless entity == current_entity

            available.empty? ? %w[pass] : %w[bid pass]
          end

          def active?
            @game.financial?(current_entity) && super
          end

          def setup
            setup_auction
          end

          def description
            'Financial Turn'
          end

          def pass_description
            'Pass (price moves left)'
          end

          # Button text on the shared amount box
          def bid_str(_corporation)
            'Buy'
          end

          # Construction Companies this Finance House may start now
          def available
            entity = current_entity
            return [] unless @game.finance_house?(entity)
            return [] if entity.cash < START_MIN

            @game.startable_construction_companies
          end

          def ipo_type(_corporation)
            :bid
          end

          # The shared auction screen and player cards call these. Starting
          # is not an auction: nothing is being auctioned and no cash is
          # committed to bids. (Auctioner's auctioning is protected, which
          # the server enforces but the browser-compiled code does not.)
          def auctioning; end

          def active_auction; end

          def committed_cash(_player, _show_hidden = false)
            0
          end

          def min_bid(_corporation)
            START_MIN
          end

          def max_bid(entity, _corporation)
            entity.cash
          end

          def process_bid(action)
            entity = action.entity
            company = action.corporation
            amount = action.price
            raise GameError, "#{entity.name} cannot start #{company&.name}" unless available.include?(company)

            valid = amount.between?(START_MIN, entity.cash) && (amount % min_increment).zero?
            unless valid
              raise GameError, 'Amount must be a multiple of ' \
                               "#{@game.format_currency(min_increment)} from " \
                               "#{@game.format_currency(START_MIN)} to " \
                               "#{@game.format_currency(entity.cash)}"
            end

            @game.start_company(entity, company, amount)
            pass!
          end

          # 11.3: taking no action moves the price one space left (down a
          # row at the left edge of the market).
          def process_pass(action)
            super
            entity = action.entity
            old_price = entity.share_price
            @game.stock_market.move_left(entity)
            @game.log_share_price(entity, old_price)
          end
        end
      end
    end
  end
end

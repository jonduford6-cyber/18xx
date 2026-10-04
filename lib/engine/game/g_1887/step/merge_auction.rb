# frozen_string_literal: true

require_relative '../../../step/base'

module Engine
  module Game
    module G1887
      module Step
        # Purchase of control: the announcer opens at the minimum bid or
        # higher; then clockwise each eligible player raises by $5 or more or
        # passes (final) until one is left. The standard bidding panel of the
        # merger screen (the survivor's card and the amount box, as 1817's
        # merger auctions) and the standard Pass button.
        class MergeAuction < Engine::Step::Base
          def actions(entity)
            return [] if !active? || entity != current_entity

            auction[:high_bid] ? %w[bid pass] : %w[bid]
          end

          def round_state
            { auction: nil }
          end

          def auction
            @round.auction
          end

          def active?
            !auction.nil?
          end

          def active_entities
            active? ? [auction[:bidders].first] : []
          end

          def description
            "Auction for control of #{auction[:survivor].name}+#{auction[:retired].name}"
          end

          def pass_description
            'Pass'
          end

          # the merger screen shows this company's card and the amount box
          def auctioning_corporation
            auction && auction[:survivor]
          end

          def min_increment
            5
          end

          def min_bid(_corporation = nil)
            auction[:high_bid] ? auction[:high_bid] + 5 : auction[:min]
          end

          def max_bid(entity, _corporation = nil)
            entity.cash - (entity.cash % 5)
          end

          def bid_str(_corporation = nil)
            'Bid'
          end

          # asked by the player cards and the shared auction screens
          def auctioning; end

          def active_auction; end

          def committed_cash(_player, _show_hidden = false)
            0
          end

          def process_bid(action)
            player = action.entity
            amount = action.price
            raise GameError, "It is #{current_entity.name}'s turn" unless player == current_entity

            fmt = ->(v) { @game.format_currency(v) }
            raise GameError, "The bid must be at least #{fmt[min_bid]}" if amount < min_bid
            raise GameError, "The bid must be a multiple of #{fmt[5]}" unless (amount % 5).zero?
            raise GameError, "#{player.name} has only #{fmt[player.cash]}" if amount > player.cash

            @log << (auction[:high_bid] ? "#{player.name} raises to #{fmt[amount]}" : "#{player.name} opens at #{fmt[amount]}")
            auction[:high_bid] = amount
            auction[:high_bidder] = player
            auction[:bidders].rotate!
            @game.finish_control_auction! if auction[:bidders].size == 1
          end

          def process_pass(action)
            player = action.entity
            raise GameError, "It is #{current_entity.name}'s turn" unless player == current_entity
            raise GameError, "#{player.name} must open the bidding" unless auction[:high_bid]

            @log << "#{player.name} passes"
            auction[:bidders].shift
            @game.finish_control_auction! if auction[:bidders].size == 1
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

require_relative '../../../step/base'
require_relative '../../../step/auctioner'

module Engine
  module Game
    module G1887
      module Step
        # The Initial Auction, adapted from The Old Prince 1871's
        # G1871::Step::Auction. Each player is dealt a face-up pile; the
        # auctioneer offers an item from their own pile, and only the two
        # players to their left may bid. If both pass, the next player after
        # them is forced to buy at face value.
        #
        # Two players (a placeholder until a better auction is designed): the
        # other player bids first or passes; if he passes the auctioneer takes
        # the item at face value; if he bids, the two alternate raises until
        # one passes and the last bidder wins at his bid.
        class Auction < Engine::Step::Base
          include Engine::Step::Auctioner
          BID_ACTIONS = %w[bid pass].freeze
          OFFER_ACTIONS = %w[offer].freeze

          attr_reader :companies, :auctioning

          def description
            'Auction off Companies'
          end

          def finished?
            @companies.empty?
          end

          # 2 players: the first auctioneer gets the larger pile, so the two
          # take turns to the very last item
          def pile_size(player = nil, first = nil)
            return @companies.size.fdiv(2).send(player == first ? :ceil : :floor) if entities.size == 2

            entities.size == 3 ? 5 : 4
          end

          def setup
            setup_auction
            @companies = @game.companies.sort_by { @game.rand }

            first = entities[@game.rand % entities.size]
            from = 0
            entities.each do |player|
              size = pile_size(player, first)
              pile = @companies[from, size]
              from += size
              @log << "Offer pile for #{player.name}: " \
                      "#{pile.map(&:name).join(', ')}"
              player.unsold_companies.concat(pile)
            end

            @log << "#{first.name} is the first auctioneer"
            @game.first_auctioneer = first
            @round.goto_entity!(first)
          end

          def available
            @auctioning ? [@auctioning] : current_entity.unsold_companies
          end

          def active_auction
            company = @auctioning
            bids = @bids[company]
            yield company, bids unless bids.empty?
          end

          def show_map
            true
          end

          def show_companies
            true
          end

          def process_offer(action)
            player = action.entity
            company = action.company
            mine = player.unsold_companies.include?(company)
            raise GameError, "#{company.name} is not in #{player.name}'s pile" unless mine

            @selected_company = company
            @auctioneer = player
            @player1 = entities[(entity_index + 1) % entities.size]
            @player2 = entities[(entity_index + 2) % entities.size]
            @receiver = entities[(entity_index + 3) % entities.size]
            @player2 = @receiver = player if two_players? # the auctioneer answers the other player's bid
            @auctioning = company
            @player1.unpass!
            @player2.unpass!

            @log << "#{player.name} offers #{company.name}"
            goto_entity!(@player1)
            auto_pass_if_forced!
          end

          # A pass after any bid ends the auction: the highest bid wins.
          # Two passes with no bid force the item on @receiver.
          def process_pass(action)
            player = action.entity
            @log << "#{player.name} passes on #{@auctioning.name}"
            player.pass!

            return win_item(highest_bid(@auctioning)) unless @bids[@auctioning].empty?
            return force_item(@auctioning) if @player1.passed? && (two_players? || @player2.passed?)

            next_bidder!
          end

          def process_bid(action)
            add_bid(action)
            next_bidder!
          end

          def active?
            !@companies.empty?
          end

          def actions(entity)
            return [] if @companies.empty?

            actions = @auctioning ? BID_ACTIONS : OFFER_ACTIONS
            entity == current_entity ? actions : []
          end

          def round_state
            { companies_pending_par: [] }
          end

          def starting_bid(company)
            company.value + min_increment
          end

          def committed_cash(_player, _show_hidden = false)
            0
          end

          def min_bid(company)
            return unless company
            return starting_bid(company) if @bids[company].empty?

            highest_bid(company).price + min_increment
          end

          def may_purchase?(_company)
            false
          end

          def may_offer?(_company)
            !@auctioning
          end

          def max_bid(player, _company)
            player.cash
          end

          # A note under the bid box of a Charter (display only): the par the
          # Finance House gets if this bid wins (the same rule as
          # finance_house_par) and the cash it starts with, the bid itself
          # (float_finance_house pays the winning bid into its treasury).
          # Every lookup is guarded: with nothing to say (no Charter, no
          # amount, the auction over) it returns nil, and it never raises
          def bid_note(company, amount)
            fh_id = company && @game.class::CHARTERS[company.id]
            fh = fh_id && @game.corporation_by_id(fh_id)
            amount = amount.to_i if amount
            return unless fh
            return unless amount&.positive?

            par = @game.finance_house_par(amount)
            return unless par

            name = fh.full_name.to_s.sub(/ \((FH|CC)\)\z/, '')
            "If this bid wins, #{name} pars at #{@game.format_currency(par.price)} and starts with " \
              "#{@game.format_currency(amount)}."
          rescue StandardError
            nil
          end

          private

          def two_players?
            entities.size == 2
          end

          def add_bid(bid)
            super
            @log << "#{bid.entity.name} bids " \
                    "#{@game.format_currency(bid.price)} for #{bid.company.name}"
          end

          # Payment goes to the bank; after_buy_company then handles the
          # Charters, Concessions and BAGS privates as before.
          def assign_item(player, company, price)
            company.owner = player
            player.companies << company
            player.spend(price, @game.bank)

            @auctioneer.unsold_companies.delete(company)
            @companies.delete(company)
            @bids.delete(company)

            @game.after_buy_company(player, company, price)
          end

          def win_item(bid)
            assign_item(bid.entity, bid.company, bid.price)
            @log << "#{bid.entity.name} wins #{bid.company.name} for " \
                    "#{@game.format_currency(bid.price)}"
            end_auction!
          end

          def force_item(company)
            value = company.value
            buyer = @receiver
            if buyer.cash < value
              buyer = richest_after_payouts(company)
              reason = ' (richest player)'
            end

            @log << "#{buyer.name} #{two_players? && !reason ? 'takes' : 'is forced to buy'} #{company.name} for " \
                    "#{@game.format_currency(value)}#{reason}"
            assign_item(buyer, company, value)
            end_auction!
          end

          # Owned privates pay out until the richest player can afford it.
          def richest_after_payouts(company)
            until (richest = entities.max_by(&:cash)).cash >= company.value
              @log << "No player can afford #{company.name}, " \
                      'privates pay their revenue'
              paid = @game.companies.sum { |c| c.owner ? c.revenue : 0 }
              raise GameError, 'No private pays any revenue' if paid.zero?

              @game.payout_companies
            end
            richest
          end

          def next_bidder!
            goto_entity!(entity_index == entities.index(@player1) ? @player2 : @player1)
            auto_pass_if_forced!
          end

          def auto_pass_if_forced!
            player = entities[entity_index]
            min_cash = min_bid(@selected_company)
            return if player.cash >= min_cash

            @log << "#{player.name} does not have " \
                    "#{@game.format_currency(min_cash)} " \
                    "(#{@game.format_currency(player.cash)})"
            @round.process_action(Engine::Action::Pass.new(player))
          end

          def end_auction!
            next_player = @player1
            goto_entity!(@player1)

            @player1.unpass!
            @player2.unpass!
            @auctioneer = @auctioning = @player1 = @player2 = @receiver = nil

            # A player with one item left offers it automatically
            return unless next_player.unsold_companies.size == 1

            company = next_player.unsold_companies.first
            @round.process_action(Engine::Action::Offer.new(next_player, company: company))
          end

          def goto_entity!(entity)
            @round.goto_entity!(entity)
          end
        end
      end
    end
  end
end

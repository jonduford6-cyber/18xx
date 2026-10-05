# frozen_string_literal: true

require 'view/game/actionable'

module View
  module Game
    module Button
      class BuyShare < Snabberb::Component
        include Actionable

        needs :share
        needs :entity
        needs :swap_share, default: nil
        needs :partial_percent, default: nil
        needs :percentages_available, default: 1
        needs :prefix, default: 'Buy'
        needs :source, default: 'Market'
        needs :action, default: Engine::Action::BuyShares
        needs :purchase_for, default: nil
        needs :borrow_from, default: nil
        needs :discounter, default: nil

        def render
          step = @game.round.active_step
          bundle = @share.to_bundle
          show_percentage = @percentages_available > 1 ||
                            (bundle.percent != bundle.corporation.share_percent && !bundle.presidents_share) ||
                            (@game.respond_to?(:shares_as_percent?) && @game.shares_as_percent?)
          reduced_price = @game.format_currency(bundle.price - @swap_share.price) if @swap_share
          if step.respond_to?(:modify_purchase_price)
            if (modified_bundle_price = step.modify_purchase_price(bundle)) == bundle.price
              modified_bundle_price = nil
            else
              modified_share_price = modified_bundle_price / bundle.num_shares
            end
          end

          text = @prefix.to_s
          text += " #{@partial_percent}% of" if @partial_percent
          counts = @game.respond_to?(:shares_as_count?) && @game.shares_as_count? # opt-in: "Buy 1 Market Share ($63)"
          if counts
            text += " #{bundle.num_shares}"
          elsif show_percentage
            text += " #{bundle.percent}%"
          end
          text += " #{@source}"
          text += ' Preferred' if @share.preferred
          text += ' Share'
          text += " (#{reduced_price} + #{@swap_share.percent}% Share)" if @swap_share
          text += " (#{@game.format_currency(modified_bundle_price)})" if modified_bundle_price
          text += " for #{@purchase_for.name}" if @purchase_for
          text += " (#{@game.format_currency(bundle.price)})" if counts && !modified_bundle_price

          process_buy = lambda do
            do_buy = lambda do
              buy_shares(@entity, bundle, share_price: modified_share_price, swap: @swap_share,
                                          purchase_for: @purchase_for, borrow_from: @borrow_from,
                                          discounter: @discounter)
            end

            if (consenter = @game.consenter_for_buy_shares(@entity, bundle))
              check_consent(@entity, consenter, do_buy)
            else
              do_buy.call
            end
          end

          h(:button, { on: { click: process_buy } }, text)
        end

        def buy_shares(entity, bundle, share_price: nil, swap: nil, purchase_for: nil, borrow_from: nil, discounter: nil)
          process_action(@action.new(entity, shares: bundle.shares, swap: swap, purchase_for: purchase_for,
                                             share_price: share_price, borrow_from: borrow_from,
                                             discounter: discounter))
        end
      end
    end
  end
end

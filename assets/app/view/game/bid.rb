# frozen_string_literal: true

# backtick_javascript: true

require 'view/game/actionable'

module View
  module Game
    module Round
      class Bid < Snabberb::Component
        include Actionable
        needs :entity
        needs :biddable

        def render
          return '' unless (step = @game.round.step_for(@entity, 'bid'))

          children = []
          children << h(:div, [step.bid_description]) if step.respond_to?(:bid_description) && step.bid_description

          min_increment = step.min_increment

          min_bid = step.min_bid(@biddable)
          max_bid = step.max_bid(@entity, @biddable)
          price_input = h(:input, style: { marginRight: '1rem' }, props: {
                            value: min_bid,
                            step: min_increment,
                            min: min_bid,
                            max: max_bid,
                            type: 'number',
                            size: [@entity.cash.to_s.size, max_bid.to_s.size].max,
                          })

          place_bid = lambda do
            process_action(Engine::Action::Bid.new(
              @entity,
              corporation: @biddable.corporation? ? @biddable : nil,
              company: @biddable.company? ? @biddable : nil,
              price: Native(price_input)[:elm][:value].to_i,
            ))
          end

          note = render_start_note(step, price_input, min_bid)

          bid_str = step.respond_to?(:bid_str) ? step.bid_str(@biddable) : 'Place Bid'
          bid_button = h(:button, { on: { click: place_bid } }, bid_str)
          children << h(:div, [price_input, bid_button])
          children.concat(note)

          h('div.center', children)
        end

        # Opt-in (1887's Finance House / Construction Company start): a step
        # that defines start_note gets two short lines under the amount box.
        # The second follows the box's input event (typing and the arrows)
        # and is written straight into the page; nothing is stored. Any error
        # here is swallowed: the lines then draw nothing, and the box, the
        # button and the start are never affected.
        def render_start_note(step, input, min_bid)
          return [] unless step.respond_to?(:start_note)

          company = @biddable
          box_id = "start_box_#{company.id}"
          amount = start_note_box_value(box_id)
          amount = min_bid unless amount.positive?
          lines = step.start_note(company, amount)
          return [] unless lines

          preview = h(:div, { attrs: { id: "start_note_#{company.id}" } }, lines[1])
          handler = proc do
            new_lines = step.start_note(company, input.JS['elm'].JS['value'].to_i)
            preview.JS['elm'].JS['textContent'] = new_lines[1] if new_lines && preview.JS['elm']
          rescue Exception # rubocop:disable Lint/RescueException
            nil
          end
          `var data = #{input}.data`
          `data.attrs = Object.assign(data.attrs || {}, { id: #{box_id} })`
          `data.on = { input: #{handler} }`
          [h(:div, { style: { marginTop: '0.4rem', fontSize: '90%' } }, [h(:div, lines[0]), preview])]
        rescue Exception # rubocop:disable Lint/RescueException
          []
        end

        # the number now in the page's amount box (a redraw keeps the typed number), 0 when there is none
        def start_note_box_value(id)
          `typeof document === 'undefined' ? 0 : (document.getElementById(#{id}) || {}).value | 0`
        end
      end
    end
  end
end

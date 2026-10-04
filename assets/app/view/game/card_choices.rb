# frozen_string_literal: true

require 'view/game/actionable'
require 'view/game/corporation'

module View
  module Game
    # Opt-in: used only when the step answers card_choices (1887's Finance
    # House and Construction Company turn). Another company's card, with the
    # acting corporation's sale and purchase buttons for that company below
    # it when the card is selected, as a Stock Round puts its buttons on cards.
    class CardChoices < Snabberb::Component
      include Actionable

      needs :corporation
      needs :selected_corporation, default: nil, store: true

      def render
        step = @game.round.active_step
        children = [h(Corporation, corporation: @corporation)]

        if @selected_corporation == @corporation
          options = step.card_choices(@corporation)
          unless options.empty?
            buttons = options.map do |choice, label|
              click = lambda do
                process_action(Engine::Action::Choose.new(step.current_entity, choice: choice))
              end
              h(:button, { style: { padding: '0.2rem 0.2rem' }, on: { click: click } }, label)
            end
            children << h('div.margined_bottom', { style: { width: '20rem' } }, buttons)
          end
        end

        h(:div, { style: { display: 'inline-block', verticalAlign: 'top' } }, children)
      end
    end
  end
end

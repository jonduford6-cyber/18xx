# frozen_string_literal: true

require 'view/game/corporation'
require 'view/game/player'

module View
  module Game
    # Opt-in (1887): the Game tab of a Stock Round drawn like the Entities
    # tab, one column per player, plus the strip of the next operating order
    # and the band of the companies not started. Mixed into Round::Stock; the
    # cards, buttons and panels are the ones the Stock Round draws anyway
    # (render_input), so every action works as before.
    module StockColumns
      LOGO_POINTS = '20,1 37,10.5 37,29.5 20,39 3,29.5 3,10.5'

      def render_stock_columns
        players = @game.player_entities
        if (i = players.map(&:name).rindex(@user&.dig(:name)))
          players = players.rotate(i)
        end
        bankrupt, players = players.partition(&:bankrupt)
        players += bankrupt

        grid = {
          style: {
            display: 'grid',
            grid: 'auto / repeat(auto-fill, minmax(20rem, 1fr))',
            gap: '1rem 1.2rem',
            marginBottom: '1.5rem',
          },
        }
        merging = @step.respond_to?(:merge_in_progress?) && @step.merge_in_progress?

        columns = @game.stock_round_columns(players).map do |player, lombard, direct, below|
          cards = [render_stock_player(player)]
          cards.concat(lombard.map { |minor| h(Corporation, corporation: minor, selectable: false) })
          cards.concat((direct + below).map { |corporation| render_stock_card(corporation, merging) })
          h(:div, cards.compact)
        end

        [render_order_strip, h('div#stock_columns', grid, columns), render_not_started(merging)].compact
      end

      def render_stock_player(player)
        card = h(Player, player: player, game: @game)
        return h(:div, [card]) unless @game.round.can_act?(player)

        h(:div, { style: { display: 'inline-block', outline: '3px solid white', outlineOffset: '1px' } }, [card])
      end

      # The same card, with the same buy / sell / par input under it, as
      # render_corporations draws
      def render_stock_card(corporation, merging)
        return if @auctioning_corporation && @auctioning_corporation != corporation
        return if @mergeable_entity && @mergeable_entity != corporation
        return if @price_protection && @price_protection.corporation != corporation

        children = []
        children.concat(render_subsidiaries)
        input = render_input(corporation) if @game.corporation_available?(corporation)
        children << h(Corporation, corporation: corporation, interactive: input || merging)
        children << input if input && @selected_corporation == corporation
        h(:div, children)
      end

      def render_not_started(merging)
        cards = @game.stock_not_started.map { |corporation| render_stock_card(corporation, merging) }.compact
        return if cards.empty?

        h(:div, { style: { marginBottom: '1.5rem' } }, [
          h(:div, { style: { fontWeight: 'bold', letterSpacing: '0.1em', marginBottom: '0.4rem' } }, 'NOT STARTED'),
          h(:div, { style: { display: 'flex', flexWrap: 'wrap', alignItems: 'flex-start', gap: '1rem 1.2rem' } }, cards),
        ])
      end

      # The next operating order: round for a Railway, rounded square for a
      # Finance House, hexagon for a Construction Company; dashed while the
      # company's marker still waits to be placed
      def render_order_strip
        items = @game.stock_order_strip
        return if items.empty?

        logos = items.map { |corporation, waiting| render_order_logo(corporation, waiting) }
        props = {
          style: { display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: '0.3rem', margin: '0.6rem 0 1rem 0' },
        }
        h('div#operating_strip', props, [h(:span, { style: { marginRight: '0.5rem' } }, 'Next operating order'), *logos])
      end

      def render_order_logo(corporation, waiting)
        shape_attrs = {
          fill: corporation.color,
          stroke: corporation.text_color,
          'stroke-width': 2,
        }
        shape_attrs['stroke-dasharray'] = '4 3' if waiting
        shape = case @game.entity_type_tag(corporation)
                when 'FH'
                  h(:rect, attrs: shape_attrs.merge(x: 2, y: 2, width: 36, height: 36, rx: 9, ry: 9))
                when 'CC'
                  h(:polygon, attrs: shape_attrs.merge(points: LOGO_POINTS))
                else
                  h(:circle, attrs: shape_attrs.merge(cx: 20, cy: 20, r: 18))
                end
        text_attrs = {
          x: 20,
          y: 24,
          'text-anchor': 'middle',
          'font-size': corporation.name.size > 3 ? 10 : 12,
          'font-weight': 'bold',
          fill: corporation.text_color,
        }
        h(:svg, { attrs: { viewBox: '0 0 40 40', width: '2.6rem', height: '2.6rem' } }, [
          shape,
          h(:text, { attrs: text_attrs }, corporation.name),
        ])
      end
    end
  end
end

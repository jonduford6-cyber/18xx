# frozen_string_literal: true

module Engine
  module Game
    module G1887
      # 11.3.4 Merge: two companies of the same tier become one. Planned
      # here (who may propose, which charter survives, the certificates
      # paired, the president) and carried out by perform_merge!; the
      # unpaired choices (Step::MergeChoices), surplus station tokens
      # (Step::MergeTokens) and trains over the limit (Step::DiscardTrain)
      # follow as steps of the Operating Round.
      module Merge
        # Tiers that may merge (2 Railways, 1 Construction Companies,
        # 0 Finance Houses)
        MERGE_TIERS = [2].freeze

        # A Railway's station limit (its charter's tokens)
        STATION_LIMIT = { 'BAGS' => 3, 'BAWR' => 3, 'BBNW' => 3, 'SFW' => 4, 'ANW' => 4, 'BAP' => 3, 'ER' => 3 }.freeze

        # Certificate units: a Railway's 10%, a Construction Company's or
        # Finance House's 20%; a president's certificate is two
        def unit_percent(corporation)
          tier(corporation) == 2 ? 10 : 20
        end

        def units_of(holder, corporation)
          holder.shares_of(corporation).sum { |s| s.percent.div(unit_percent(corporation)) }
        end

        def merge_ready?(corporation)
          corporation.floated? && !corporation.retired && on_market?(corporation) &&
            completed_operating_turn?(corporation) &&
            (corporation.id != 'BAWR' || held_back_bawr.empty?) # 10.4: not while BAWR's exchange certificates wait
        end

        # The pairs a Finance House or Construction Company may propose on
        # its turn
        def merge_pairs(proposer)
          return [] unless financial?(proposer)

          pairs =
            if finance_house?(proposer)
              houses = @corporations.select { |c| finance_house?(c) && c != proposer && merge_ready?(c) }
              houses = [] unless merge_ready?(proposer)
              houses.map { |c| [proposer, c] } + presided_pairs(proposer, 1)
            else
              presided_pairs(proposer, 2)
            end
          pairs.select { |a, _| self.class::MERGE_TIERS.include?(tier(a)) }
        end

        def presided_pairs(proposer, tier_number)
          @corporations.select { |c| tier(c) == tier_number && merge_ready?(c) }
                       .combination(2).to_a.select { |a, b| a.owner == proposer || b.owner == proposer }
        end

        # The charter that survives: the higher station limit (Railways),
        # then the higher price; both if still tied (the proposer chooses)
        def merge_survivors(a, b)
          key = ->(c) { [tier(c) == 2 ? STATION_LIMIT.fetch(c.id, 0) : 0, c.share_price.price] }
          order = key.call(a) <=> key.call(b)
          return [a] if order.positive?
          return [b] if order.negative?

          [a, b]
        end

        # Merge buttons: [choice, label, survivor, retired], only for merges
        # in which someone would reach the president threshold
        def merge_options(proposer)
          merge_pairs(proposer).flat_map do |a, b|
            survivors = merge_survivors(a, b)
            survivors.filter_map do |survivor|
              retired = survivor == a ? b : a
              next unless merge_plan(proposer, survivor, retired)[:president]

              label = "Merge #{a.name}+#{b.name}"
              label += " (#{survivor.name} stays)" if survivors.size > 1
              ["merge:#{survivor.id}:#{retired.id}", label, survivor, retired]
            end
          end
        end

        # The player at the top of a company's chain (Lombard Street's owner
        # when Lombard Street is at the top)
        def top_player(corporation)
          actor = control_actor(corporation)
          actor&.minor? ? actor.owner : actor
        end

        # Holders in pairing order: the proposer's top player, the other
        # players clockwise, corporations by descending price (11.1), Lombard
        # Street, the bank pool. The two predecessors' treasuries are counted
        # apart (their certificates stay in the merged treasury).
        def merge_order(proposer, a, b)
          first = top_player(proposer)
          players = first&.player? ? @players.rotate(@players.index(first)) : @players
          corps = @corporations.reject { |c| c.closed? || [a, b].include?(c) }
                               .select { |c| (units_of(c, a) + units_of(c, b)).positive? }
          players + corps.sort + [lombard].compact + [share_pool]
        end

        def merge_units(holder, survivor, retired)
          units_of(holder, survivor) + units_of(holder, retired)
        end

        def merge_plan(proposer, survivor, retired)
          rows = merge_order(proposer, survivor, retired).map { |h| [h, merge_units(h, survivor, retired)] }
          rows = rows.reject { |row| row[1].zero? }
          president = rows.find { |row| row[0] != share_pool && row[1].div(2) >= 2 }&.first
          treasury = merge_units(survivor, survivor, retired) + merge_units(retired, survivor, retired)
          { rows: rows, treasury: treasury, president: president }
        end

        # The space whose price is nearest the average of the two (every
        # price appears once on 1887's market); exactly between two, the lower
        def merge_price(survivor, retired)
          average = (survivor.share_price.price + retired.share_price.price) / 2.0
          stock_market.market.flatten.compact.min_by { |sp| [(sp.price - average).abs, sp.price] }
        end

        def perform_merge!(proposer, survivor, retired)
          plan = merge_plan(proposer, survivor, retired)
          raise GameError, "Nobody would hold #{survivor.name}'s president's certificate" unless plan[:president]

          operated = merge_operated_this_round?(survivor) || merge_operated_this_round?(retired)
          prices = [survivor, retired].map { |c| c.share_price.price }
          @log << "-- #{proposer.name} merges #{survivor.name} and #{retired.name}: #{survivor.name} keeps its charter --"

          merge_assets!(survivor, retired)
          merge_certificates!(survivor, retired, plan)
          new_price = merge_price(survivor, retired)
          stock_market.move(survivor, new_price.coordinates, force: true)
          survivor.share_price.corporations.delete(survivor)
          survivor.share_price.corporations << survivor # the bottom of its stack
          @log << "#{survivor.name}'s share price moves to #{format_currency(new_price.price)} " \
                  "(average of #{prices.map { |p| format_currency(p) }.join(' and ')})"
          merge_tokens!(survivor, retired) if tier(survivor) == 2
          retire!(retired)
          merge_unpaired!(survivor, plan)

          held = survivor.shares.map(&:corporation).uniq - [survivor]
          held.each { |c| check_presidency(c) }
          merge_timing!(survivor, retired, operated)
          recheck_operating_order
        end

        def merge_operated_this_round?(corporation)
          return false unless @round.is_a?(Engine::Round::Operating)

          index = @round.entities.index(corporation)
          index && index <= @round.entity_index
        end

        # Cash, trains, privates and the certificates held in other companies
        def merge_assets!(survivor, retired)
          retired.spend(retired.cash, survivor) if retired.cash.positive?
          retired.trains.dup.each { |t| buy_train(survivor, t, :free) }
          retired.companies.dup.each do |company|
            retired.companies.delete(company)
            company.owner = survivor
            survivor.companies << company
          end
          retired.shares.reject { |s| [survivor, retired].include?(s.corporation) }.each do |share|
            share_pool.transfer_shares(share.to_bundle, survivor, allow_president_change: false)
          end
        end

        # Every two units of a holder become one new certificate; the first
        # holder with two new units takes the president's certificate
        def merge_certificates!(survivor, retired, plan)
          [survivor, retired].each do |corp|
            corp.share_holders.keys.each do |holder| # all certificates back to their own treasury
              holder.shares_of(corp).dup.each do |share|
                share_pool.transfer_shares(share.to_bundle, corp, allow_president_change: false) unless share.owner == corp
              end
            end
          end
          ordinary = survivor.shares_of(survivor).reject(&:president)
          plan[:rows].each do |holder, units|
            count = units.div(2)
            next if count.zero?

            if holder == plan[:president]
              share_pool.transfer_shares(survivor.presidents_share.to_bundle, holder, allow_president_change: false)
              survivor.owner = holder
              count -= 2
            end
            ordinary.shift(count).each { |s| share_pool.transfer_shares(s.to_bundle, holder, allow_president_change: false) }
            @log << "#{holder.name} receives #{units.div(2) * unit_percent(survivor)}% of #{survivor.name}" \
                    "#{units.odd? ? ' and has an unpaired certificate' : ''}"
          end
          @log << "#{plan[:president].name} becomes the president of #{survivor.name}"
        end

        # Railways: the standard token merger (as 1828, 1867): where both have
        # a token in the same city one is removed, the retired charter's
        # tokens become the survivor's; over the survivor's station limit its
        # president first removes the excess (Step::MergeTokens, the shared
        # ReduceTokens step)
        def merge_tokens!(survivor, retired)
          step = @round.steps.find { |s| s.is_a?(G1887::Step::MergeTokens) }
          shared = survivor.tokens.select(&:used).map(&:city) & retired.tokens.select(&:used).map(&:city)
          shared.each do |city|
            @log << "#{survivor.name} and #{retired.name} both have a token in #{city.hex.id}: one stays, #{survivor.name}'s"
          end
          step.remove_duplicate_tokens(survivor, [retired])
          if step.tokens_above_limits?(survivor, [retired])
            @round.corporations_removing_tokens = [survivor, retired]
            excess = (survivor.tokens + retired.tokens).count(&:used) - STATION_LIMIT.fetch(survivor.id)
            @log << "#{survivor.name} must remove #{excess} station token#{excess == 1 ? '' : 's'}"
          else
            step.move_tokens_to_surviving(survivor, [retired], check_tokenable: false)
          end
        end

        # The retired charter leaves the game for now: its certificates,
        # marker, tokens and treasury
        def retire!(corporation)
          corporation.share_price&.corporations&.delete(corporation)
          corporation.retire!
          @log << "#{corporation.name} is retired; its certificates and marker leave the game"
        end

        # Unpaired units: the predecessors' treasury is credited half the
        # price; the bank pool's is discarded; the others choose
        # (Step::MergeChoices) in stock market order
        def merge_unpaired!(survivor, plan)
          half = survivor.share_price.price.div(2)
          if plan[:treasury].odd?
            @bank.spend(half, survivor)
            @log << "#{survivor.name} receives #{format_currency(half)} for the unpaired certificate in its treasury"
          end
          holders = plan[:rows].select { |_, u| u.odd? }.map(&:first)
          @log << 'The unpaired certificate in the bank pool is discarded' if holders.delete(share_pool)
          corps = holders.select(&:corporation?).sort
          players = @players.select { |p| holders.include?(p) }
          rest = holders - corps - players
          return unless @round.respond_to?(:merge_unpaired=)

          # certificates nobody received go to the bank pool (the merged
          # treasury keeps only its own pairs and its unpaired unit); unpaired
          # holders who buy take theirs from there
          kept = plan[:treasury].div(2) + (plan[:treasury] % 2)
          spare = survivor.shares_of(survivor).reject(&:president).drop(kept)
          spare.each { |s| share_pool.transfer_shares(s.to_bundle, share_pool, allow_president_change: false) }
          @log << "#{spare.sum(&:percent)}% of #{survivor.name} that nobody received goes to the bank pool" unless spare.empty?
          @round.merge_spare = spare.size
          @round.merge_unpaired = (corps + players + rest).map { |h| [h, survivor] }
        end

        # 11.3.4: the merged corporation operates this round only if neither
        # predecessor has; the retired one never does again
        def merge_timing!(survivor, retired, operated)
          return unless @round.is_a?(Engine::Round::Operating)

          later = @round.entities.drop(@round.entity_index + 1)
          @round.entities.delete(retired) if later.include?(retired)
          @round.entities.delete(survivor) if operated && later.include?(survivor)
        end

        def merge_half_price(survivor)
          survivor.share_price.price.div(2)
        end

        # The honour-system confirm on the merge button when the two
        # presidents (the players at the top of the chains) differ
        def consenter_for_choice(entity, choice, _label)
          return super unless choice.to_s.start_with?('merge:')

          _, a, b = choice.split(':')
          tops = [a, b].map { |id| top_player(corporation_by_id(id)) }.uniq
          return if tops.size < 2

          tops.find { |t| t != top_player(entity) }
        end
      end
    end
  end
end

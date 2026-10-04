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
        MERGE_TIERS = [0, 1, 2].freeze

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
          return [] unless merge_style == :friendly # a variant replaces the Merge action

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

        # ---- Merger Round (the merger variants) ----

        # The holders a player answers for: himself, the corporations at the
        # top of whose chain he is, and Lombard Street if he owns it
        def player_holders(player)
          [player] + @corporations.select { |c| !c.closed? && top_player(c) == player } +
            (lombard&.owner == player ? [lombard] : [])
        end

        # A player's units in two companies (not counting a company's own
        # treasury)
        def player_units(player, a, b)
          player_holders(player).sum do |h|
            (h == a ? 0 : units_of(h, a)) + (h == b ? 0 : units_of(h, b))
          end
        end

        # Same-tier pairs that may be put to a Merger Round: both have
        # operated, neither has merged this round, the pair has not been
        # rejected this round
        def merger_round_pairs
          merged = @round.respond_to?(:merged) ? @round.merged : []
          rejected = @round.respond_to?(:rejected) ? @round.rejected : []
          @corporations.select { |c| merge_ready?(c) && !merged.include?(c) }
                       .group_by { |c| tier(c) }.values
                       .flat_map { |list| list.combination(2).to_a }
                       .reject { |a, b| rejected.any? { |pair| pair.sort_by(&:name) == [a, b].sort_by(&:name) } }
        end

        # [choice, label, survivor, retired] for the player's proposals
        def proposal_options(player, verb)
          merger_round_pairs.flat_map do |a, b|
            next [] unless proposal_allowed?(player, a, b)

            survivors = merge_survivors(a, b)
            survivors.filter_map do |survivor|
              retired = survivor == a ? b : a
              next if merge_style == :contested && !merge_plan(player, survivor, retired)[:president]
              next if merge_style == :control && !control_eligible?(player, survivor, retired)

              label = "#{verb} #{a.name}+#{b.name}"
              label += " (#{survivor.name} stays)" if survivors.size > 1
              ["propose:#{survivor.id}:#{retired.id}", label, survivor, retired]
            end
          end
        end

        def proposal_allowed?(player, a, b)
          return player_units(player, a, b).positive? if merge_style == :contested

          merge_survivors(a, b).any? { |s| control_eligible?(player, s, s == a ? b : a) }
        end

        # Voting blocks, clockwise from the proposer: each player's own
        # units, then each corporation he answers for (cast by him), then
        # Lombard Street if he owns it. A company's own treasury and the
        # bank pool do not vote here.
        def vote_blocks(proposer, a, b)
          @players.rotate(@players.index(proposer)).flat_map do |player|
            player_holders(player).filter_map do |h|
              n = (h == a ? 0 : units_of(h, a)) + (h == b ? 0 : units_of(h, b))
              [player, h, n] if n.positive?
            end
          end
        end

        # The bank pool votes yes if its units would become certificates of
        # higher total value, no if lower, and abstains if equal
        def pool_vote(survivor, retired)
          units = merge_units(share_pool, survivor, retired)
          return [nil, 0] if units.zero?

          before = (units_of(share_pool, survivor) * survivor.share_price.price) +
                   (units_of(share_pool, retired) * retired.share_price.price)
          after = units.div(2) * merge_price(survivor, retired).price
          return [:yes, units] if after > before
          return [:no, units] if after < before

          [:abstain, units]
        end

        # Contested merger: after the last block, the pool votes; more yes
        # than no passes and the merger happens at once (the proposing player
        # first in the pairing order); otherwise the pair is rejected for
        # this round
        def decide_vote!
          proposal = @round.proposal
          survivor = proposal[:survivor]
          retired = proposal[:retired]
          yes = @round.votes_yes
          no = @round.votes_no
          pool, pool_votes = pool_vote(survivor, retired)
          yes += pool_votes if pool == :yes
          no += pool_votes if pool == :no
          passed = yes > no
          pool_text = pool ? "pool: #{pool}" : 'pool: none'
          @log << "-- Vote on #{survivor.name}+#{retired.name}: #{yes} yes, #{no} no (#{pool_text}): " \
                  "#{passed ? 'passed' : 'failed'} --"
          @round.proposal = nil
          if passed
            @round.merged.concat([survivor, retired])
            perform_merge!(proposal[:proposer], survivor, retired)
          else
            @round.rejected << [survivor, retired]
          end
        end

        # ---- Purchase of control ----

        # Half the market value of the units held by players, corporations
        # and Lombard Street (not a company's own treasury, not the pool), in
        # $5 steps (rounded up)
        def control_min_bid(a, b)
          value = [a, b].sum do |c|
            (@players + @corporations + [lombard].compact).sum { |h| h == c ? 0 : units_of(h, c) } * c.share_price.price
          end
          half = (value + 1).div(2)
          half + ((5 - (half % 5)) % 5)
        end

        # The units a winner would hold: his own pairs, at least the
        # president's certificate (2 units). The missing units come from the
        # certificates the pairing leaves unissued: first the merged
        # company's own treasury, then those nobody receives (the pool).
        # nil if there are not enough.
        def control_winner_units(player, survivor, retired)
          plan = merge_plan(player, survivor, retired)
          own = merge_units(player, survivor, retired).div(2)
          missing = [2 - own, 0].max
          others = plan[:rows].sum { |h, u| h == player ? 0 : u.div(2) }
          kept = plan[:treasury].div(2) + (plan[:treasury] % 2)
          ordinary = (tier(survivor) == 2 ? 10 : 5) - 2
          left = ordinary - others - [own - 2, 0].max # ordinary certificates not given to holders
          left - (kept - [missing, kept].min) >= 0 ? [own, 2].max : nil
        end

        # Who may announce or bid: enough cash for the minimum bid + $5, the
        # certificate limit and the 60% control limit kept after winning, and
        # enough unissued certificates for his president's certificate
        def control_eligible?(player, survivor, retired, min = control_min_bid(survivor, retired))
          return false if player.cash < min + 5

          units = control_winner_units(player, survivor, retired)
          return false unless units

          certs_now = player.shares.count { |s| [survivor, retired].include?(s.corporation) }
          return false if num_certs(player) - certs_now + (units - 1) > cert_limit(player)

          others = player_holders(player).reject { |h| h == player || [survivor, retired].include?(h) }
                                         .sum { |h| merge_units(h, survivor, retired).div(2) }
          (units + others) * unit_percent(survivor) <= self.class::CONTROL_LIMIT
        end

        # The winner pays the holders in proportion to their units (players
        # in cash, corporations and Lombard Street into their treasuries;
        # not the pool or a company's own treasury); rounded down; the
        # remainder goes to the merged treasury
        def control_payments(survivor, retired, amount)
          holders = (@players + @corporations + [lombard].compact).filter_map do |h|
            units = (h == survivor ? 0 : units_of(h, survivor)) + (h == retired ? 0 : units_of(h, retired))
            [h, units] if units.positive?
          end
          total = holders.sum(&:last)
          paid = holders.map { |h, u| [h, (amount * u).div(total), u] }
          [paid, amount - paid.sum { |_, x, _| x }]
        end

        def finish_control_auction!
          auction = @round.auction
          winner = auction[:high_bidder]
          amount = auction[:high_bid]
          survivor = auction[:survivor]
          retired = auction[:retired]
          @log << "#{winner.name} wins control for #{format_currency(amount)}; the holders are paid"
          paid, remainder = control_payments(survivor, retired, amount)
          paid.each do |holder, x, units|
            next unless x.positive?

            winner.spend(x, holder) unless holder == winner
            @log << "#{holder.name} receives #{format_currency(x)} (#{units} unit#{units == 1 ? '' : 's'})"
          end
          @round.auction = nil
          @round.merged.concat([survivor, retired])
          perform_merge!(winner, survivor, retired, president: winner)
          return unless remainder.positive?

          winner.spend(remainder, survivor)
          @log << "#{survivor.name} receives the remainder, #{format_currency(remainder)}"
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

        def perform_merge!(proposer, survivor, retired, president: nil)
          plan = merge_plan(proposer, survivor, retired)
          plan[:president] = president if president # Purchase of control: the auction's winner
          plan[:forced_president] = !president.nil?
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

          # companies the retired charter presided over: its certificates
          # are now the survivor's
          @corporations.each { |c| c.owner = survivor if c.owner == retired }
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
          rows = plan[:rows]
          rows += [[plan[:president], 0]] if plan[:forced_president] && rows.none? { |h, _| h == plan[:president] }
          missing = 0
          rows.each do |holder, units|
            count = units.div(2)
            if holder == plan[:president]
              share_pool.transfer_shares(survivor.presidents_share.to_bundle, holder, allow_president_change: false)
              survivor.owner = holder
              missing = [2 - count, 0].max # Purchase of control: made up from the unissued certificates
              count = [count - 2, 0].max
            end
            ordinary.shift(count).each { |s| share_pool.transfer_shares(s.to_bundle, holder, allow_president_change: false) }
            next if units.zero?

            @log << "#{holder.name} receives #{units.div(2) * unit_percent(survivor)}% of #{survivor.name}" \
                    "#{units.odd? ? ' and has an unpaired certificate' : ''}"
          end
          plan[:missing] = missing
          @log << "#{plan[:president].name} becomes the president of #{survivor.name}"
          return unless missing.positive?

          @log << "#{plan[:president].name} receives #{missing * unit_percent(survivor)}% more of #{survivor.name} " \
                  "from its unissued certificates to make up the president's certificate"
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
          (@completed_operating_turns ||= []).delete(corporation)
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
          kept -= [plan[:missing].to_i, kept].min # Purchase of control: the winner's missing units, treasury first
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

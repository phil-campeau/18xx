# frozen_string_literal: true

require_relative '../../../step/buy_sell_par_shares'
require_relative '../../../step/share_buying'
# require_relative '../../../step/base'
# require_relative '../../../share_buying'
# require_relative '../../../programmer'
# require_relative '../../../action/buy_company'
# require_relative '../../../action/buy_shares'
# require_relative '../../../action/par'
# require_relative '../../../step/base'
# require_relative '../player'
# require_relative '../game'

# For 18 India, first action is sell any, then buy
# NOTE: This section isn't completed, in progress for stock round
module Engine
  module Game
    module G18India
      module Step
        class SellOnceThenBuyCerts < Engine::Step::BuySellParShares
          include Engine::Step::ShareBuying

          def actions(entity)
            return [] unless entity == current_entity
            # return ['sell_shares'] if must_sell?(entity)

            actions = []
            if selling_round?
              # sell anything, only limitation is president share can't be in market
              # move 'must sell' ceck to this section to verify player below cert limit
              actions << 'sell_shares' if can_sell_any?(entity)
              actions << 'sell_company' if can_sell_any_companies?(entity)
            else
              # buy 1 share from market
              # buy 1 or 2 shares from same IPO row
              # buy any number of same type from player hand
              # buy 1 railroad bond
              actions << 'buy_shares' if can_buy_any?(entity)
              actions << 'par' if can_ipo_any?(entity)
              actions << 'buy_company' if can_buy_any_companies?(entity)
            end

            actions << 'pass' unless actions.empty?
            actions
          end

          def selling_round?
            return false if @round.round_num == 1 # no selling during first SR

            # add First round and first SR logic
            false
          end

          def description
            if selling_round?
              'May Sell Certificates (first turn of Stock Round only)'
            else
              'Buy Certificates'
            end
          end

          def pass_description
            if @round.current_actions.empty?
              'Pass (Certificates)'
            else
              'Done (Certificates)'
            end
          end

          def purchasable_companies(_entity)
            []
          end

          def can_buy_company?(_player, _company)
            # Unlike other games, you may buy after selling during SR
            # !did_sell?(company, player)
            true
          end

          def can_buy_any_companies?(entity)
            return false if bought? ||
              !entity.cash.positive? ||
              @game.num_certs(entity) >= @game.cert_limit(entity)

            @game.companies.any? { |c| c.owner == @game.bank && !did_sell?(c, entity) }
          end

          def get_par_prices(_entity, corp)
            @game.par_prices(corp)
          end

          def process_buy_shares(action)
            super
            @game.check_new_layer
          end

          def process_buy_company(action)
            player = action.entity
            company = action.company
            price = action.price
            owner = company.owner

            raise GameError, "Cannot buy #{company.name} from #{owner.name}" unless owner == @game.bank

            company.owner = player

            player.companies << company
            player.spend(price, owner)
            track_action(action, company)
            @log << "#{player.name} buys #{company.name} from #{owner.name} for #{@game.format_currency(price)}"
          end

          # Returns if a share can be bought via a normal buy actions
          # If a player has sold shares they cannot buy in many 18xx games
          def can_buy?(entity, bundle)
            return super unless @game.class::PRESIDENT_SALES_TO_MARKET
            return unless bundle&.buyable

            corporation = bundle.corporation
            entity.cash >= bundle.price && can_gain?(entity, bundle) &&
              !@round.players_sold[entity][corporation] &&
              (can_buy_multiple?(entity, corporation, bundle.owner) || !bought?) &&
              can_buy_presidents_share?(entity, bundle, corporation)
          end

          # can only buy president's share if player already has at least one share
          def can_buy_presidents_share?(entity, share, corporation)
            return true if share.percent != corporation.presidents_percent ||
              share.owner != @game.share_pool

            difference = share.percent - corporation.share_percent
            num_shares_needed = difference / corporation.share_percent
            existing_shares = entity.percent_of(corporation) || 0
            existing_shares > num_shares_needed
          end

          def can_sell?(entity, bundle)
            return super unless @game.class::PRESIDENT_SALES_TO_MARKET
            return unless bundle

            corporation = bundle.corporation

            timing = @game.check_sale_timing(entity, bundle)

            timing &&
              !(@game.class::MUST_SELL_IN_BLOCKS && @round.players_sold[entity][corporation] == :now) &&
              can_sell_order? &&
              @game.share_pool.fit_in_bank?(bundle) &&
              can_dump?(entity, bundle)
          end

          # can't sell partial president's share to pool if pool is empty
          def can_dump?(entity, bundle)
            corp = bundle.corporation
            return true if !bundle.presidents_share || bundle.percent >= corp.presidents_percent

            max_shares = corp.player_share_holders.reject { |p, _| p == entity }.values.max || 0
            return true if max_shares > 10

            pool_shares = @game.share_pool.percent_of(corp) || 0
            pool_shares.positive?
          end

          def process_sell_company(action)
            company = action.company
            player = action.entity
            raise GameError, "Cannot sell #{company.id}" unless can_sell_company?(company)

            sell_company(player, company, action.price)
            track_action(action, company)
          end

          def sell_price(entity)
            return 0 unless can_sell_company?(entity)

            entity.value - @game.class::COMPANY_SALE_FEE
          end

          def can_sell_any_companies?(entity)
            !bought? && sellable_companies(entity).any?
          end

          def sellable_companies(entity)
            return [] unless @game.turn > 1
            return [] unless entity.player?

            entity.companies
          end

          def can_sell_company?(entity)
            return false unless entity.company?
            return false if entity.owner == @game.bank
            return false unless @game.turn > 1

            true
          end

          def sell_company(player, company, price)
            company.owner = @game.bank
            player.companies.delete(company)
            @game.bank.spend(price, player) if price.positive?
            @log << "#{player.name} sells #{company.name} to bank for #{@game.format_currency(price)}"
            @round.players_sold[player][company] = :now
          end

          def make_player_hand_buyable(entity)
            return [] unless entity.player?
          end
        end
      end
    end
  end
end

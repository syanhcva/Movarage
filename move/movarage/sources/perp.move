module movarage::perp {
    use std::error;
    use std::math128;
    use std::signer;
    use std::vector;
    use std::string::{String};
    use std::timestamp;

    use aptos_std::table::{Self, Table};

    use aptos_framework::aptos_account;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::object::{Self, ObjectCore};
    use aptos_framework::type_info;

    use movarage::mosaic_caller;
    use simple_lending::lending;

    struct PerpConfig has key {
        resource_signer_cap: SignerCapability,
        // The value of the leverage level supports one digit after the decimal point, e.g. 1, 1.2, 1.5, 5,...
        // The stored value of the leverage level is multiplied by 10 to remove the decimal point.
        // e.g. 1 -> 10, 1.5 -> 15, 5 -> 50
        min_levarage_level: u16,
        max_leverage_level: u16,
        daily_interest_bips: u32, // 1000 bips = 1%
        liquidation_ltv: u16,
        interest_recipient: address,
    }

    struct Position has store, drop, copy {
        id: u64,
        user_address: address,
        source_token_type_name: String,
        target_token_type_name: String,
        leverage_level: u16,
        user_paid_amount: u64,
        borrow_amount: u64,
        deposit_amount: u64,
        entry_price: u64,
        closed_price: u64,
        is_closed: bool,
        opened_at: u64, // timestamp in seconds
        closed_at: u64, // timestamp in seconds
        interest_calculation_from: u64, // timestamp in seconds
        collected_interest_amount: u64,
    }

    struct UserPositions has store {
        open_position_ids: vector<u64>,
        closed_position_ids: vector<u64>,
    }

    struct PositionsStore has key {
        next_position_id: u64,
        positions: Table<u64, Position>, // key is position ID
        // use for client to query open positions of user more convenient
        users_positions: Table<address, UserPositions>,
        position_open_events: EventHandle<PositionOpenEvent>,
        position_close_events: EventHandle<PositionCloseEvent>,
    }

    #[event]
    struct PositionOpenEvent has drop, store {
        position_id: u64,
        user_address: address,
        source_token_type_name: String,
        target_token_type_name: String,
        leverage_level: u16,
        user_paid_amount: u64,
        borrow_amount: u64,
        deposit_amount: u64,
        entry_price: u64,
        opened_at: u64,
    }

    #[event]
    struct PositionCloseEvent has drop, store {
        position_id: u64,
        closed_price: u64,
        closed_at: u64,
    }

    const RESOURCE_ACCOUNT_SEED: vector<u8> = b"leverage";

    const E_NOT_AUTHORIZED: u64 = 1;
    const E_PERMISSION_DENIED: u64 = 2;
    const E_INVALID_POSITION_AMOUNT: u64 = 3;
    const E_INVALID_LEVERAGE_LEVEL: u64 = 4;
    const E_NOT_OWNER_POSITION: u64 = 5;
    const E_NOT_FOUND_POSITION: u64 = 6;
    const E_CLOSED_POSITION: u64 = 7;
    const E_MISMATCH_SOURCE_TOKEN_TYPE: u64 = 8;
    const E_MISMATCH_TARGET_TOKEN_TYPE: u64 = 9;
    const E_LIQUIDATION_LTV_NOT_REACH: u64 = 9;

    const BIPS_PER_1_PERCENT: u64 = 1000;
    const SECONDS_PER_DAY: u64 = 86400;

    fun init_module(owner: &signer) {
        let (_, resource_signer_cap) = account::create_resource_account(owner, RESOURCE_ACCOUNT_SEED);

        move_to(owner, PerpConfig {
            resource_signer_cap: resource_signer_cap,
            min_levarage_level: 10,
            max_leverage_level: 50,
            daily_interest_bips: 20, // 0.02%
            liquidation_ltv: 95,
            // temporarily use the address of movarage as interest_recipient, need to update later by admin
            interest_recipient: @movarage,
        });

        move_to(owner, PositionsStore {
            next_position_id: 1,
            positions: table::new<u64, Position>(),
            users_positions: table::new<address, UserPositions>(),
            position_open_events: new_event_handle<PositionOpenEvent>(owner),
            position_close_events: new_event_handle<PositionCloseEvent>(owner),
        });
    }

    entry fun set_interest_recipient(sender: &signer, interest_recipient: address) acquires PerpConfig {
        assert!(is_owner(sender), E_PERMISSION_DENIED);

        borrow_global_mut<PerpConfig>(@movarage).interest_recipient = interest_recipient;
    }

    public entry fun open_position_with_mosaic<SourceToken, TargetToken, Z,
                                                P1H1, P1H2,
                                                P2H1, P2H2,
                                                P3H1, P3H2
    >(
        sender: &signer,
        user_pay_amount: u64,
        leverage_level: u16,
        path_1_1: vector<u64>, path_1_2: vector<u64>, path_1_3: vector<u64>,
        path_2_1: vector<u64>, path_2_2: vector<u64>, path_2_3: vector<u64>,
        path_3_1: vector<u64>, path_3_2: vector<u64>, path_3_3: vector<u64>,
        fee_recipient: address,
        fee_in_bps: u64,
        min_amount_out: u64,
        amount_in_usd: String,
        amount_out_usd: String,
    ) acquires PerpConfig, PositionsStore {
        assert!(user_pay_amount > 0, E_INVALID_POSITION_AMOUNT);

        let perp_config = borrow_global_mut<PerpConfig>(@movarage);

        assert!(leverage_level >= perp_config.min_levarage_level, E_INVALID_LEVERAGE_LEVEL);
        assert!(leverage_level <= perp_config.max_leverage_level, E_INVALID_LEVERAGE_LEVEL);

        let source_token_amount_to_swap: u64 = user_pay_amount * (leverage_level as u64) / 10;
        let source_token_amount_to_borrow = user_pay_amount * ((leverage_level as u64) - 10) / 10;

        if (source_token_amount_to_borrow > 0) {
            borrow_lending<SourceToken>(perp_config, source_token_amount_to_borrow);
        };

        // transfer source token from user to contract vault
        aptos_account::transfer_coins<SourceToken>(sender, account::get_signer_capability_address(&perp_config.resource_signer_cap), user_pay_amount);

        // swap source token to target token (result in contract vault)
        let swapped_target_token_amount = mosaic_caller::swap<
            SourceToken, TargetToken, Z,
            P1H1, P1H2, P2H1, P2H2, P3H1, P3H2,
        >(
            &account::create_signer_with_capability(&perp_config.resource_signer_cap),
            path_1_1, path_1_2, path_1_3,
            path_2_1, path_2_2, path_2_3,
            path_3_1, path_3_2, path_3_3,
            fee_recipient, fee_in_bps,
            source_token_amount_to_swap, min_amount_out,
            amount_in_usd, amount_out_usd,
        );

        // save data
        let positions_store = borrow_global_mut<PositionsStore>(@movarage);
        let sender_address = signer::address_of(sender);
        let position_id = positions_store.next_position_id;
        let now_seconds = timestamp::now_seconds();
        let position = Position {
            id: position_id,
            user_address: sender_address,
            source_token_type_name: type_info::type_name<SourceToken>(),
            target_token_type_name: type_info::type_name<TargetToken>(),
            leverage_level: leverage_level,
            user_paid_amount: user_pay_amount,
            deposit_amount: swapped_target_token_amount,
            borrow_amount: source_token_amount_to_borrow,
            entry_price: calculate_exchange_price<TargetToken>(source_token_amount_to_swap, swapped_target_token_amount),
            closed_price: 0,
            is_closed: false,
            opened_at: now_seconds,
            closed_at: 0,
            collected_interest_amount: 0,
            interest_calculation_from: now_seconds, 
        };
        table::add(&mut positions_store.positions, position_id, position);
        positions_store.next_position_id = positions_store.next_position_id + 1;

        let users_positions = &mut positions_store.users_positions;
        if (table::contains(users_positions, sender_address)) {
            let user_positions = table::borrow_mut(users_positions, sender_address);
            vector::push_back(&mut user_positions.open_position_ids, position_id);
        } else {
            let open_position_ids = vector::empty<u64>();
            vector::push_back(&mut open_position_ids, position_id);
            table::add(users_positions, sender_address, UserPositions {
                open_position_ids: open_position_ids,
                closed_position_ids: vector::empty(),
            });
        };

        event::emit_event(&mut positions_store.position_open_events, PositionOpenEvent {
            position_id: position.id,
            user_address: position.user_address,
            source_token_type_name: position.source_token_type_name,
            target_token_type_name: position.target_token_type_name,
            leverage_level: position.leverage_level,
            user_paid_amount: position.user_paid_amount,
            borrow_amount: position.borrow_amount,
            deposit_amount: position.deposit_amount,
            entry_price: position.entry_price,
            opened_at: position.opened_at,
        });
    }

    public entry fun modify_position<SourceToken>(
        sender: &signer, 
        position_id: u64,
        new_leverage_level: u16,
    ) acquires PerpConfig, PositionsStore {
        let perp_config = borrow_global_mut<PerpConfig>(@movarage);

        assert!(new_leverage_level >= perp_config.min_levarage_level, E_INVALID_LEVERAGE_LEVEL);
        assert!(new_leverage_level <= perp_config.max_leverage_level, E_INVALID_LEVERAGE_LEVEL);

        let positions = &mut borrow_global_mut<PositionsStore>(@movarage).positions;
        let position = table::borrow_mut(positions, position_id);
        assert!(!position.is_closed, E_CLOSED_POSITION);

        let sender_address = signer::address_of(sender);
        assert!(sender_address == position.user_address, E_NOT_OWNER_POSITION);

        if (new_leverage_level == position.leverage_level) return;

        let total_amount = position.user_paid_amount + position.borrow_amount;
        let new_user_paid_amount = total_amount * ((new_leverage_level as u64) - 10) / 10;
        let now_seconds = timestamp::now_seconds();
        let interest_accrued_amount = calculate_interest_amount(
            now_seconds - position.interest_calculation_from, 
            perp_config.daily_interest_bips,
            position.borrow_amount,
        );

        if (new_user_paid_amount > position.user_paid_amount) {
            let user_paid_amount_more = new_user_paid_amount - position.user_paid_amount;
            aptos_account::transfer_coins<SourceToken>(
                sender, 
                account::get_signer_capability_address(&perp_config.resource_signer_cap), 
                user_paid_amount_more + interest_accrued_amount,
            );
            payback_lending<SourceToken>(perp_config, user_paid_amount_more);
        } else {
            let user_borrow_amount_more = position.user_paid_amount - new_user_paid_amount;
            let resource_signer_cap = &perp_config.resource_signer_cap;
            let resource_signer = account::create_signer_with_capability(resource_signer_cap);

            aptos_account::transfer_coins<SourceToken>(&resource_signer, signer::address_of(sender), user_borrow_amount_more);
            aptos_account::transfer_coins<SourceToken>(sender, perp_config.interest_recipient, interest_accrued_amount);
            borrow_lending<SourceToken>(perp_config, user_borrow_amount_more);
        };

        position.user_paid_amount = new_user_paid_amount;
        position.borrow_amount = total_amount - new_user_paid_amount;
        position.collected_interest_amount = interest_accrued_amount;
        position.interest_calculation_from = now_seconds;
    }

    public entry fun close_position_with_mosaic<SourceToken, TargetToken, Z,
                                                P1H1, P1H2,
                                                P2H1, P2H2,
                                                P3H1, P3H2,
    >(
        sender: &signer,
        position_id: u64,
        path_1_1: vector<u64>, path_1_2: vector<u64>, path_1_3: vector<u64>,
        path_2_1: vector<u64>, path_2_2: vector<u64>, path_2_3: vector<u64>,
        path_3_1: vector<u64>, path_3_2: vector<u64>, path_3_3: vector<u64>,
        fee_recipient: address,
        fee_in_bps: u64,
        min_amount_out: u64,
        amount_in_usd: String,
        amount_out_usd: String,
    ) acquires PerpConfig, PositionsStore {
        let positions_store = borrow_global_mut<PositionsStore>(@movarage);
        let positions = &positions_store.positions;

        assert!(table::contains(positions, position_id), E_NOT_FOUND_POSITION);

        let position = table::borrow(positions, position_id);
        assert!(!position.is_closed, E_CLOSED_POSITION);
        assert!(position.source_token_type_name == type_info::type_name<SourceToken>(), E_MISMATCH_SOURCE_TOKEN_TYPE);
        assert!(position.target_token_type_name == type_info::type_name<TargetToken>(), E_MISMATCH_TARGET_TOKEN_TYPE);

        let sender_address = signer::address_of(sender);
        assert!(sender_address == position.user_address, E_NOT_OWNER_POSITION);

        let perp_config = borrow_global<PerpConfig>(@movarage);
        let swapped_source_token_amount = mosaic_caller::swap<
            TargetToken, SourceToken, Z,
            P1H1, P1H2, P2H1, P2H2, P3H1, P3H2,
        >(
            &account::create_signer_with_capability(&perp_config.resource_signer_cap),
            path_1_1, path_1_2, path_1_3,
            path_2_1, path_2_2, path_2_3,
            path_3_1, path_3_2, path_3_3,
            fee_recipient, fee_in_bps,
            position.deposit_amount, min_amount_out,
            amount_in_usd, amount_out_usd,
        );

        let user_remaining_source_token_amount: u64 = 0;
        let source_token_amount_to_payback: u64 = 0;
        let now_seconds = timestamp::now_seconds();
        let interest_accrued_amount: u64 = 0;

        if (swapped_source_token_amount >= position.borrow_amount) {
            source_token_amount_to_payback = position.borrow_amount;
            user_remaining_source_token_amount = swapped_source_token_amount - position.borrow_amount;

            interest_accrued_amount = calculate_interest_amount(
                now_seconds - position.interest_calculation_from,
                perp_config.daily_interest_bips,
                position.borrow_amount,
            );
            if (user_remaining_source_token_amount <= interest_accrued_amount) {
                interest_accrued_amount = user_remaining_source_token_amount;
                user_remaining_source_token_amount = 0;
            } else {
                user_remaining_source_token_amount = user_remaining_source_token_amount - interest_accrued_amount;
            }
        } else {
            source_token_amount_to_payback = swapped_source_token_amount;
        };

        if (source_token_amount_to_payback > 0) {
            payback_lending<SourceToken>(perp_config, source_token_amount_to_payback);
        };

        let resource_signer_cap = &perp_config.resource_signer_cap;
        let resource_signer = account::create_signer_with_capability(resource_signer_cap);

        if (interest_accrued_amount > 0) {
            aptos_account::transfer_coins<SourceToken>(&resource_signer, perp_config.interest_recipient, interest_accrued_amount);
        };

        if (user_remaining_source_token_amount > 0) {
            aptos_account::transfer_coins<SourceToken>(&resource_signer, position.user_address, user_remaining_source_token_amount);
        };

        // update data
        let position_mut = table::borrow_mut(&mut positions_store.positions, position_id);
        position_mut.is_closed = true;
        position_mut.closed_at = now_seconds;
        position_mut.closed_price = calculate_exchange_price<TargetToken>(swapped_source_token_amount, position_mut.deposit_amount);
        position_mut.collected_interest_amount = position_mut.collected_interest_amount + interest_accrued_amount;

        let users_positions = &mut positions_store.users_positions;
        if (table::contains(users_positions, sender_address)) {
            let user_positions = table::borrow_mut(users_positions, sender_address);
            vector::remove_value(&mut user_positions.open_position_ids, &position_id);
            vector::push_back(&mut user_positions.closed_position_ids, position_id);
        };

        event::emit_event(&mut positions_store.position_close_events, PositionCloseEvent {
            position_id: position_mut.id,
            closed_price: position_mut.closed_price,
            closed_at: position_mut.closed_at,
        });
    }

    public entry fun liquidate_position<SourceToken, TargetToken, Z,
                                        P1H1, P1H2,
                                        P2H1, P2H2,
                                        P3H1, P3H2,
    >(
        sender: &signer,
        position_id: u64,
        path_1_1: vector<u64>, path_1_2: vector<u64>, path_1_3: vector<u64>,
        path_2_1: vector<u64>, path_2_2: vector<u64>, path_2_3: vector<u64>,
        path_3_1: vector<u64>, path_3_2: vector<u64>, path_3_3: vector<u64>,
        min_amount_out: u64,
        amount_in_usd: String,
        amount_out_usd: String,
    ) acquires PerpConfig, PositionsStore {
        assert!(is_owner(sender), E_PERMISSION_DENIED);

        let positions_store = borrow_global_mut<PositionsStore>(@movarage);
        let positions = &positions_store.positions;

        let position = table::borrow(positions, position_id);
        assert!(!position.is_closed, E_CLOSED_POSITION);
        assert!(position.source_token_type_name == type_info::type_name<SourceToken>(), E_MISMATCH_SOURCE_TOKEN_TYPE);
        assert!(position.target_token_type_name == type_info::type_name<TargetToken>(), E_MISMATCH_TARGET_TOKEN_TYPE);

        let perp_config = borrow_global<PerpConfig>(@movarage);
        let swapped_source_token_amount = mosaic_caller::swap<
            TargetToken, SourceToken, Z,
            P1H1, P1H2, P2H1, P2H2, P3H1, P3H2,
        >(
            &account::create_signer_with_capability(&perp_config.resource_signer_cap),
            path_1_1, path_1_2, path_1_3,
            path_2_1, path_2_2, path_2_3,
            path_3_1, path_3_2, path_3_3,
            @movarage, 0, // TODO: no need to take fee in this case, should take liquidation fee
            position.deposit_amount, min_amount_out,
            amount_in_usd, amount_out_usd,
        );

        let ltv = calculate_ltv(position.borrow_amount, swapped_source_token_amount);
        assert!((ltv as u16) < perp_config.liquidation_ltv, E_LIQUIDATION_LTV_NOT_REACH);

        let user_remaining_source_token_amount: u64 = 0;
        let source_token_amount_to_payback: u64 = 0;
        let now_seconds = timestamp::now_seconds();
        let interest_accrued_amount = calculate_interest_amount(
            now_seconds - position.opened_at,
            perp_config.daily_interest_bips,
            position.borrow_amount,
        );

        if (swapped_source_token_amount >= position.borrow_amount) {
            source_token_amount_to_payback = position.borrow_amount;
            user_remaining_source_token_amount = swapped_source_token_amount - position.borrow_amount;
            if (user_remaining_source_token_amount <= interest_accrued_amount) {
                interest_accrued_amount = user_remaining_source_token_amount;
                user_remaining_source_token_amount = 0;
            } else {
                user_remaining_source_token_amount = user_remaining_source_token_amount - interest_accrued_amount;
            }
        } else {
            source_token_amount_to_payback = swapped_source_token_amount;
        };

        if (source_token_amount_to_payback > 0) {
            payback_lending<SourceToken>(perp_config, source_token_amount_to_payback);
        };

        let resource_signer_cap = &perp_config.resource_signer_cap;
        let resource_signer = account::create_signer_with_capability(resource_signer_cap);

        if (interest_accrued_amount > 0) {
            aptos_account::transfer_coins<SourceToken>(&resource_signer, perp_config.interest_recipient, interest_accrued_amount);
        };

        if (user_remaining_source_token_amount > 0) {
            aptos_account::transfer_coins<SourceToken>(&resource_signer, position.user_address, user_remaining_source_token_amount);
        };

        // update data
        let position_mut = table::borrow_mut(&mut positions_store.positions, position_id);
        position_mut.is_closed = true;
        position_mut.closed_at = now_seconds;
        position_mut.closed_price = calculate_exchange_price<TargetToken>(swapped_source_token_amount, position_mut.deposit_amount);

        let users_positions = &mut positions_store.users_positions;
        if (table::contains(users_positions, position_mut.user_address)) {
            let user_positions = table::borrow_mut(users_positions, position_mut.user_address);
            vector::remove_value(&mut user_positions.open_position_ids, &position_id);
            vector::push_back(&mut user_positions.closed_position_ids, position_id);
        };

        event::emit_event(&mut positions_store.position_close_events, PositionCloseEvent {
            position_id: position_mut.id,
            closed_price: position_mut.closed_price,
            closed_at: position_mut.closed_at,
        });
    }

    fun calculate_ltv(borrow_amount: u64, total_amount: u64): u64 {
        return borrow_amount * 10_000 / total_amount
    }

    fun borrow_lending<Token>(perp_config: &PerpConfig, amount: u64) {
        let resource_signer_cap = &perp_config.resource_signer_cap;
        lending::borrow<Token>(account::get_signer_capability_address(resource_signer_cap), amount);
    }

    fun payback_lending<Token>(perp_config: &PerpConfig, amount: u64) {
        let resource_signer_cap = &perp_config.resource_signer_cap;
        let resource_signer = account::create_signer_with_capability(resource_signer_cap);
        lending::payback<Token>(&resource_signer, amount);
    }

    fun calculate_interest_amount(duration_seconds: u64, daily_interest_bips: u32, borrow_amount: u64): u64 {
        if (borrow_amount == 0) return 0;

        let interest_accrued_day =
            duration_seconds / SECONDS_PER_DAY + if (duration_seconds % SECONDS_PER_DAY > 0) 1 else 0;

        return borrow_amount * interest_accrued_day * (daily_interest_bips as u64) / BIPS_PER_1_PERCENT / 100
    }

    fun calculate_exchange_price<QuoteToken>(base_token_amount: u64, quote_token_amount: u64): u64 {
        let quote_token_decimals = (coin::decimals<QuoteToken>() as u128);
        // use u128 to avoid overflow value of u64
        return (((base_token_amount as u128) * (math128::pow(10, quote_token_decimals)) / (quote_token_amount as u128)) as u64)
    }

    fun is_owner(sender: &signer): bool {
        if (object::object_exists<ObjectCore>(@movarage)) {
            let object = object::address_to_object<ObjectCore>(@movarage);
            return object::is_owner(object, signer::address_of(sender))
        } else {
            return signer::address_of(sender) == @movarage
        }
    }

    fun new_event_handle<T: store + drop>(owner: &signer): EventHandle<T> {
        if (object::is_object(signer::address_of(owner))) {
            return object::new_event_handle<T>(owner)
        } else {
            return account::new_event_handle<T>(owner)
        }
    }

    //---------------------------Views---------------------------
    struct LeverageConfigView {
        min_levarage_level: u16,
        max_leverage_level: u16,
        daily_interest_bips: u32,
        liquidation_ltv: u16,
    }

    struct PositionView has drop {
        id: u64,
        user_address: address,
        source_token_type_name: String,
        target_token_type_name: String,
        leverage_level: u16,
        user_paid_amount: u64,
        borrow_amount: u64,
        deposit_amount: u64,
        entry_price: u64,
        closed_price: u64,
        is_closed: bool,
        opened_at: u64, // timestamp in seconds
        closed_at: u64, // timestamp in seconds
        daily_interest_bips: u32,
        interest_accrued_amount: u64,
    }

    #[view]
    public fun get_leverage_config(): LeverageConfigView acquires PerpConfig {
        let perp_config = borrow_global<PerpConfig>(@movarage);

        return LeverageConfigView {
            min_levarage_level: perp_config.min_levarage_level,
            max_leverage_level: perp_config.max_leverage_level,
            daily_interest_bips: perp_config.daily_interest_bips,
            liquidation_ltv: perp_config.liquidation_ltv,
        }
    }

    #[view]
    public fun get_min_leverage_level(): u16 acquires PerpConfig {
        return borrow_global<PerpConfig>(@movarage).min_levarage_level
    }

    #[view]
    public fun get_max_leverage_level(): u16 acquires PerpConfig {
        return borrow_global<PerpConfig>(@movarage).max_leverage_level
    }

    #[view]
    public fun get_user_open_position_ids(user_addr: address): vector<u64> acquires PositionsStore {
        let users_positions = &borrow_global<PositionsStore>(@movarage).users_positions;

        if (table::contains(users_positions, user_addr)) {
            return table::borrow(users_positions, user_addr).open_position_ids
        } else {
            return vector::empty<u64>()
        }
    }

    #[view]
    public fun get_user_closed_position_ids(user_addr: address): vector<u64> acquires PositionsStore {
        let users_positions = &borrow_global<PositionsStore>(@movarage).users_positions;

        if (table::contains(users_positions, user_addr)) {
            return table::borrow(users_positions, user_addr).closed_position_ids
        } else {
            return vector::empty<u64>()
        }
    }

    #[view]
    public fun get_position_details(position_id: u64): PositionView acquires PerpConfig, PositionsStore {
        let positions = &borrow_global<PositionsStore>(@movarage).positions;
        assert!(table::contains(positions, position_id), E_NOT_FOUND_POSITION);

        let position = table::borrow(positions, position_id);
        let daily_interest_bips = borrow_global<PerpConfig>(@movarage).daily_interest_bips;
        let interest_accrued_amount = if (position.is_closed) {
            position.collected_interest_amount
        } else {
            position.collected_interest_amount + calculate_interest_amount(
                timestamp::now_seconds() - position.interest_calculation_from,
                daily_interest_bips,
                position.borrow_amount,
            )
        };

        return PositionView {
            id: position.id,
            user_address: position.user_address,
            source_token_type_name: position.source_token_type_name,
            target_token_type_name: position.target_token_type_name,
            leverage_level: position.leverage_level,
            user_paid_amount: position.user_paid_amount,
            borrow_amount: position.borrow_amount,
            deposit_amount: position.deposit_amount,
            entry_price: position.entry_price,
            closed_price: position.closed_price,
            is_closed: position.is_closed,
            opened_at: position.opened_at,
            closed_at: position.closed_at,
            daily_interest_bips: daily_interest_bips,
            interest_accrued_amount: interest_accrued_amount,
        }
    }

    //---------------------------Tests---------------------------
    #[test_only]
    public fun initialize_for_test(owner: &signer) {
        init_module(owner);
    }

    #[test_only]
    public fun set_interest_recipient_for_test(sender: &signer, interest_recipient: address) acquires PerpConfig {
        set_interest_recipient(sender, interest_recipient);
    }

    #[test_only]
    public fun get_resource_account_address(): address acquires PerpConfig {
        return account::get_signer_capability_address(&borrow_global<PerpConfig>(@movarage).resource_signer_cap)
    }

    #[test_only]
    public fun extract_position(position: PositionView): (
        u64, address, String, String, u16, u64, u64, u64, u64, u64, bool, u64, u64, u32, u64
    ) {
        return (
            position.id,
            position.user_address,
            position.source_token_type_name,
            position.target_token_type_name,
            position.leverage_level,
            position.user_paid_amount,
            position.borrow_amount,
            position.deposit_amount,
            position.entry_price,
            position.closed_price,
            position.is_closed,
            position.opened_at,
            position.closed_at,
            position.daily_interest_bips,
            position.interest_accrued_amount,
        )
    }
}
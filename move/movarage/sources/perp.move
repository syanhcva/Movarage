module movarage::perp {
    use std::error;
    use std::signer;
    use std::vector;
    use std::string::{Self, String};

    use aptos_std::table::{Self, Table};

    use aptos_framework::guid;
    use aptos_framework::aptos_account;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::resource_account;
    use aptos_framework::type_info::{Self, TypeInfo};

    use aggregator_caller::mosaic as mosaic_caller;
    use simple_lending::lending;

    struct Position has store {
        id: u64,
        user: address,
        source_token_type_name: String,
        target_token_type_name: String,
        leverage_level: u16,
        user_amount: u64,
        deposit_amount: u64,
        borrow_amount: u64,
        is_closed: bool,
    }

    struct LeverageContainer has key {
        resource_signer_cap: SignerCapability,
        max_leverage_level: u16,
        next_position_id: u64,
        positions: Table<u64, Position>,
        user_open_positions: Table<address, vector<u64>>,
    }

    const RESOURCE_ACCOUNT_SEED: vector<u8> = b"leverage";

    const E_NOT_AUTHORIZED: u64 = 1;
    const E_INVALID_POSITION_AMOUNT: u64 = 2;
    const E_INVALID_LEVERAGE_LEVEL: u64 = 3;
    const E_MISMATCH_AMOUNT_MOSAIC: u64 = 4;
    const E_NOT_FOUND_POSITION: u64 = 5;
    const E_CLOSED_POSITION: u64 = 6;

    fun init_module(owner: &signer) {
        let (_, resource_signer_cap) = account::create_resource_account(owner, RESOURCE_ACCOUNT_SEED);

        move_to(owner, LeverageContainer{
            resource_signer_cap: resource_signer_cap,
            max_leverage_level: 5,
            next_position_id: 1,
            positions: table::new<u64, Position>(),
            // use for client to query open positions of user more convenient
            user_open_positions: table::new<address, vector<u64>>(),
        });
    }

    public entry fun open_position_with_mosaic<SourceToken, TargetToken, Z,
                                                P1H1, P1H2,
                                                P2H1, P2H2,
                                                P3H1, P3H2
    >(
        sender: &signer,
        amount: u64,
        leverage_level: u16,
        path_1_1: vector<u64>, path_1_2: vector<u64>, path_1_3: vector<u64>,
        path_2_1: vector<u64>, path_2_2: vector<u64>, path_2_3: vector<u64>,
        path_3_1: vector<u64>, path_3_2: vector<u64>, path_3_3: vector<u64>,
        fee_recipient: address,
        fee_in_bps: u64,
        amount_in: u64,
        min_amount_out: u64,
        amount_in_usd: String,
        amount_out_usd: String,
    ) acquires LeverageContainer {
        assert!(amount > 0, E_INVALID_POSITION_AMOUNT);
        assert!(leverage_level > 0, E_INVALID_LEVERAGE_LEVEL);

        let leverage_container = borrow_global_mut<LeverageContainer>(@movarage);
        assert!(leverage_level <= leverage_container.max_leverage_level, E_INVALID_LEVERAGE_LEVEL);

        let source_token_amount_to_swap: u64 = amount * (leverage_level as u64);
        assert!(source_token_amount_to_swap == amount_in, E_MISMATCH_AMOUNT_MOSAIC);

        let source_token_amount_to_borrow = amount * ((leverage_level as u64) - 1);

        // borrow source token from lending contract
        borrow<SourceToken>(leverage_container, source_token_amount_to_borrow);

        // transfer source token to contract vault
        aptos_account::transfer_coins<SourceToken>(sender, account::get_signer_capability_address(&leverage_container.resource_signer_cap), amount);

        // swap source token to target token (result in contract vault)
        let swapped_target_token_amount = mosaic_caller::swap<
            SourceToken, TargetToken, Z,
            P1H1, P1H2, P2H1, P2H2, P3H1, P3H2,
        >(
            &account::create_signer_with_capability(&leverage_container.resource_signer_cap),
            path_1_1, path_1_2, path_1_3,
            path_2_1, path_2_2, path_2_3,
            path_3_1, path_3_2, path_3_3,
            fee_recipient, fee_in_bps,
            amount_in, min_amount_out,
            amount_in_usd, amount_out_usd,
        );

        // save data
        let sender_address = signer::address_of(sender);
        let position_id = leverage_container.next_position_id;
        let position = Position {
            id: leverage_container.next_position_id,
            user: sender_address,
            source_token_type_name: type_info::type_name<SourceToken>(),
            target_token_type_name: type_info::type_name<TargetToken>(),
            leverage_level: leverage_level,
            user_amount: amount,
            deposit_amount: swapped_target_token_amount,
            borrow_amount: source_token_amount_to_borrow,
            is_closed: false,
        };
        table::add(&mut leverage_container.positions, leverage_container.next_position_id, position);
        leverage_container.next_position_id = leverage_container.next_position_id + 1;

        let user_open_positions = &mut leverage_container.user_open_positions;
        if (table::contains(user_open_positions, sender_address)) {
            let open_position_ids = table::borrow_mut(user_open_positions, sender_address);
            vector::push_back(open_position_ids, position_id);
        } else {
            let open_position_ids = vector::empty<u64>();
            vector::push_back(&mut open_position_ids, position_id);
            table::add(user_open_positions, sender_address, open_position_ids);
        }

        // TODO: emit event
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
        amount_in: u64,
        min_amount_out: u64,
        amount_in_usd: String,
        amount_out_usd: String,
    ) acquires LeverageContainer {
        let leverage_container = borrow_global_mut<LeverageContainer>(@movarage);
        let positions = &leverage_container.positions;

        assert!(table::contains(positions, position_id), E_NOT_FOUND_POSITION);

        let position = table::borrow(positions, position_id);

        assert!(!position.is_closed, E_CLOSED_POSITION);

        let swapped_source_token_amount = mosaic_caller::swap<
            TargetToken, SourceToken, Z,
            P1H1, P1H2, P2H1, P2H2, P3H1, P3H2,
        >(
            &account::create_signer_with_capability(&leverage_container.resource_signer_cap),
            path_1_1, path_1_2, path_1_3,
            path_2_1, path_2_2, path_2_3,
            path_3_1, path_3_2, path_3_3,
            fee_recipient, fee_in_bps,
            amount_in, min_amount_out,
            amount_in_usd, amount_out_usd,
        );

        let user_remaining_source_token_amount: u64 = 0;
        let source_token_amount_to_payback: u64 = 0;

        if (swapped_source_token_amount >= position.borrow_amount) {
            user_remaining_source_token_amount = swapped_source_token_amount - position.borrow_amount;
            // TODO: calculate fee later
            source_token_amount_to_payback = position.borrow_amount;
        } else {
            source_token_amount_to_payback = swapped_source_token_amount;
        };

        payback<SourceToken>(leverage_container, source_token_amount_to_payback);

        if (user_remaining_source_token_amount > 0) {
            let resource_signer_cap = &leverage_container.resource_signer_cap;
            let resource_signer = account::create_signer_with_capability(resource_signer_cap);
            aptos_account::transfer_coins<SourceToken>(&resource_signer, position.user, user_remaining_source_token_amount);
        };

        // update data
        let position_mut = table::borrow_mut(&mut leverage_container.positions, position_id);
        position_mut.is_closed = true;

        let sender_address = signer::address_of(sender);
        let user_open_positions = &mut leverage_container.user_open_positions;
        if (table::contains(user_open_positions, sender_address)) {
            let open_position_ids = table::borrow(user_open_positions, sender_address);
            let new_open_position_ids: vector<u64> = vector::filter(*open_position_ids, |id| {
                *id != position_id
            });
            table::upsert(user_open_positions, sender_address, new_open_position_ids)
        };

        // TODO: emit event
    }

    fun borrow<Token>(leverage_container: &LeverageContainer, amount: u64) {
        let resource_signer_cap = &leverage_container.resource_signer_cap;
        lending::borrow<Token>(account::get_signer_capability_address(resource_signer_cap), amount);
    }

    fun payback<Token>(leverage_container: &LeverageContainer, amount: u64) {
        let resource_signer_cap = &leverage_container.resource_signer_cap;
        let resource_signer = account::create_signer_with_capability(resource_signer_cap);
        lending::payback<Token>(&resource_signer, amount);
    }

    #[view]
    public fun get_max_leverage_level(): u16 acquires LeverageContainer {
        return borrow_global<LeverageContainer>(@movarage).max_leverage_level
    }

    #[view]
    public fun get_user_open_position_ids(user_addr: address): vector<u64> acquires LeverageContainer {
        let user_open_positions = &borrow_global<LeverageContainer>(@movarage).user_open_positions;

        if (table::contains(user_open_positions, user_addr)) {
            return *table::borrow(user_open_positions, user_addr)
        } else {
            return vector::empty<u64>()
        }
    }

    #[view]
    public fun get_position_details(position_id: u64): (String, String, u16, u64, bool) acquires LeverageContainer {
        let positions = &borrow_global<LeverageContainer>(@movarage).positions;

        assert!(table::contains(positions, position_id), E_NOT_FOUND_POSITION);

        let position = table::borrow(positions, position_id);

        return (
            position.source_token_type_name, 
            position.target_token_type_name, 
            position.leverage_level,
            position.user_amount,
            position.is_closed,
        )
    }

    //---------------------------Tests---------------------------
    #[test_only]
    public fun initialize_for_test(owner: &signer) {
        init_module(owner);
    }

    #[test_only]
    public fun get_resource_account_address(): address acquires LeverageContainer {
        return account::get_signer_capability_address(&borrow_global<LeverageContainer>(@movarage).resource_signer_cap)
    }
}
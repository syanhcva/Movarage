#[test_only]
module movarage::test_perp {
    use std::signer;
    use std::string::{Self, String};
    use std::vector;

    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin, MintCapability};
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::aptos_account;
    use aptos_framework::type_info;

    use movarage::perp;
    use aggregator_caller::mosaic as mosaic_caller;
    use simple_lending::lending;

    struct MoveCoin {}
    
    struct USDC {}

    struct CoinsCap has key {
        move_mint_cap: MintCapability<MoveCoin>,
        usdc_mint_cap: MintCapability<USDC>,
    }

    #[test(aptos_framework = @aptos_framework, source = @movarage, simple_lending = @simple_lending, user = @0x100)]
    public fun test_get_max_leverage_level(
        aptos_framework: &signer, 
        source: &signer,
        simple_lending: &signer,
        user: &signer,
    ) {
        setup_test(aptos_framework, source, simple_lending, user);
        assert!(perp::get_max_leverage_level() == 5, 42);
    }

    #[test(aptos_framework = @aptos_framework, source = @movarage, simple_lending = @simple_lending, user = @0x100, fee_recipient = @0x101)]
    public fun test_happy_case(
        aptos_framework: &signer, 
        source: &signer,
        simple_lending: &signer,
        user: &signer,
        fee_recipient: &signer,
    ) acquires CoinsCap {
        setup_test(aptos_framework, source, simple_lending, user);

        mint_move_to_account(&lending::get_resource_signer(), 1_000_000_000); // 10 move
        mint_move_to_account(user, 200_000_000); // 2 move
        mint_usdc_to_account(&mosaic_caller::get_resource_signer(), 2_000_000_000); // 20 USDC
        mint_move_to_account(&mosaic_caller::get_resource_signer(), 1_000_000_000); // 10 move
        mosaic_caller::set_swap_rate<MoveCoin, USDC>(200); // 1 move = 2 USDC

        //==================================================================
        //                      OPEN POSITION
        //==================================================================
        perp::open_position_with_mosaic<MoveCoin, USDC, USDC,
                                        MoveCoin, USDC,
                                        MoveCoin, USDC,
                                        MoveCoin, USDC,
        >(
            user,
            100_000_000, // 1 move
            5,
            vector::empty(), vector::empty(), vector::empty(),
            vector::empty(), vector::empty(), vector::empty(),
            vector::empty(), vector::empty(), vector::empty(),
            signer::address_of(fee_recipient), 0,
            500_000_000, 400_000_000,
            string::utf8(b"10"), string::utf8(b"10"),
        );

        // assert opened position data
        let user_open_position_ids = perp::get_user_open_position_ids(signer::address_of(user));
        assert!(vector::length(&user_open_position_ids) == 1, 42);
        assert!(*vector::borrow(&user_open_position_ids, 0) == 1, 42);
        let (
            source_token_type_name, 
            target_token_type_name,
            leverage_level,
            user_amount,
            is_closed,
        ) = perp::get_position_details(1);
        assert!(source_token_type_name == type_info::type_name<MoveCoin>(), 42);
        assert!(target_token_type_name == type_info::type_name<USDC>(), 42);
        assert!(leverage_level == 5, 42);
        assert!(!is_closed, 42);

        // assert coin amount in user account and contracts
        // lending contract borrows 4 move -> remain 6
        assert!(coin::balance<MoveCoin>(lending::get_resource_account_address()) == 600_000_000, 42);
        // user opens position with 1 move -> remain 1 move
        assert!(coin::balance<MoveCoin>(signer::address_of(user)) == 100_000_000, 42);
        // perp contract should has 5 * 2 USDC = 10 USDC and 0 move
        assert!(coin::balance<USDC>(perp::get_resource_account_address()) == 1_000_000_000, 42);
        assert!(coin::balance<MoveCoin>(perp::get_resource_account_address()) == 0, 42);

        //==================================================================
        //                      CLOSE POSITION
        //==================================================================
        mosaic_caller::set_swap_rate<USDC, MoveCoin>(100); // 1 move = 1 USDC
        perp::close_position_with_mosaic<MoveCoin, USDC, USDC,
                                USDC, MoveCoin,
                                USDC, MoveCoin,
                                USDC, MoveCoin,
        >(
            user,
            1,
            vector::empty(), vector::empty(), vector::empty(),
            vector::empty(), vector::empty(), vector::empty(),
            vector::empty(), vector::empty(), vector::empty(),
            signer::address_of(fee_recipient), 0,
            1000_000_000, 400_000_000,
            string::utf8(b"10"), string::utf8(b"10"),
        );
        // assert opened position data
        user_open_position_ids = perp::get_user_open_position_ids(signer::address_of(user));
        assert!(vector::length(&user_open_position_ids) == 0, 42);
        (
            source_token_type_name, 
            target_token_type_name,
            leverage_level,
            user_amount,
            is_closed,
        ) = perp::get_position_details(1);
        assert!(source_token_type_name == type_info::type_name<MoveCoin>(), 42);
        assert!(target_token_type_name == type_info::type_name<USDC>(), 42);
        assert!(leverage_level == 5, 42);
        assert!(is_closed, 42);

        // assert coin amount in user account and contracts
        // lending contract: borrowed tokens has been paybacked -> 10 move 
        assert!(coin::balance<MoveCoin>(lending::get_resource_account_address()) == 1_000_000_000, 42);
        // user: have more 5 move -> 7 move (2 initial move)
        assert!(coin::balance<MoveCoin>(signer::address_of(user)) == 700_000_000, 42);
        // perp: no token
        assert!(coin::balance<USDC>(perp::get_resource_account_address()) == 0, 42);
        assert!(coin::balance<MoveCoin>(perp::get_resource_account_address()) == 0, 42);
    }

    fun setup_test(
        aptos_framework: &signer, 
        source: &signer,
        simple_lending: &signer,
        user: &signer,
    ) {
        account::create_account_for_test(signer::address_of(source));
        account::create_account_for_test(signer::address_of(simple_lending));
        account::create_account_for_test(signer::address_of(user));

        init_coins(source);

        perp::initialize_for_test(source);
        mosaic_caller::initialize_for_test(source);
        lending::initialize_for_test(simple_lending);

        lending::add_address_to_whitelist(perp::get_resource_account_address());
    }

    fun init_coins(source: &signer) {
        let move_mint_cap = init_coin<MoveCoin>(source, string::utf8(b"Move Coin"), string::utf8(b"MOVE"));
        let usdc_mint_cap = init_coin<USDC>(source, string::utf8(b"USDC"), string::utf8(b"USDC"));

        move_to(source, CoinsCap {
            move_mint_cap,
            usdc_mint_cap,
        });
    }

    fun init_coin<CoinType>(source: &signer, name: String, symbol: String): MintCapability<CoinType> {
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<CoinType>(
            source,
            name,
            symbol,
            8,
            false,
        );
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_freeze_cap(freeze_cap);

        return mint_cap
    }

    fun mint_move_to_account(account: &signer, amount: u64) acquires CoinsCap {
        mint_coins_to_account<MoveCoin>(account, amount, &borrow_global<CoinsCap>(@movarage).move_mint_cap);
    }

    fun mint_usdc_to_account(account: &signer, amount: u64) acquires CoinsCap {
        mint_coins_to_account<USDC>(account, amount, &borrow_global<CoinsCap>(@movarage).usdc_mint_cap);
    }

    fun mint_coins_to_account<CoinType>(account: &signer, amount: u64, mint_cap: &MintCapability<CoinType>) {
        if (!coin::is_account_registered<CoinType>(signer::address_of(account))) {
            coin::register<CoinType>(account);
        };

        let coins = coin::mint<CoinType>(amount, mint_cap);
        coin::deposit(signer::address_of(account), coins);
    }
}
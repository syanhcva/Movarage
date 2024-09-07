#[test_only]
module movarage::test_perp {
    use std::signer;
    use std::string::{Self, String};
    use std::vector;

    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin, MintCapability};
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::aptos_account;

    use movarage::perp;
    use aggregator_caller::mosaic as mosaic_caller;
    use simple_lending::lending;

    struct MoveCoin {}
    
    struct USDC {}

    struct CoinsCap has key {
        move_mint_cap: MintCapability<MoveCoin>,
        usdc_mint_cap: MintCapability<USDC>,
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

        // perp::open_position_with_mosaic<MoveCoin, USDC, USDC,
        //                                 MoveCoin, USDC,
        //                                 MoveCoin, USDC,
        //                                 MoveCoin, USDC,
        // >(
        //     user,
        //     100_000_000,
        //     5,
        //     vector::empty(), vector::empty(), vector::empty(),
        //     vector::empty(), vector::empty(), vector::empty(),
        //     vector::empty(), vector::empty(), vector::empty(),
        //     signer::address_of(fee_recipient), 100,
        //     500_000_000, 400_000_000,
        //     string::utf8(b"10"), string::utf8(b"10"),
        // )
    }

    fun setup_test(
        aptos_framework: &signer, 
        source: &signer,
        simple_lending: &signer,
        user: &signer,
    ) acquires CoinsCap {
        account::create_account_for_test(signer::address_of(source));
        account::create_account_for_test(signer::address_of(simple_lending));
        account::create_account_for_test(signer::address_of(user));

        init_coins(source);

        perp::initialize_for_test(source);
        mosaic_caller::initialize_for_test(source);
        lending::initialize_for_test(simple_lending);

        mint_move_to_account(&lending::get_resource_signer(), 1_000_000_000);
        mint_usdc_to_account(&lending::get_resource_signer(), 2_000_000_000);

        assert!(coin::balance<MoveCoin>(lending::get_resource_account_address()) == 1_000_000_000, 42);
        assert!(coin::balance<USDC>(lending::get_resource_account_address()) == 2_000_000_000, 42);
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
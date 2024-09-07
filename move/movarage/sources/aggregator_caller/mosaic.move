module aggregator_caller::mosaic {
    friend movarage::perp;

    use std::vector;
    use std::string::String;

    public(friend) fun swap0<X, Y, Z,
                            P1H1, P1H2, 
                            P2H1, P2H2, 
                            P3H1, P3H2,
    >(
        sender: &signer,
        path_1_1: vector<u64>, path_1_2: vector<u64>, path_1_3: vector<u64>,
        path_2_1: vector<u64>, path_2_2: vector<u64>, path_2_3: vector<u64>,
        path_3_1: vector<u64>, path_3_2: vector<u64>, path_3_3: vector<u64>,
        fee_recipient: address,
        fee_in_bps: u64,
        amount_in: u64,
        min_amount_out: u64,
        amount_in_usd: String,
        amount_out_usd: String,
    ): u64 {
        use mosaic::router;

        router::swap_generic_v4<X, Y, Z,
                            P1H1, P1H2, P2H1, P2H2, P3H1, P3H2,
                            P1H1, P1H2, P2H1, P2H2, P3H1, P3H2,
                            P1H1, P1H2, P2H1, P2H2, P3H1, P3H2,
                            P1H1, P1H2, P2H1, P2H2, P3H1, P3H2,
                            P1H1, P1H2, P2H1, P2H2,
        >(
            sender,
            path_1_1, path_1_2, path_1_3,
            path_2_1, path_2_2, path_2_3,
            path_3_1, path_3_2, path_3_3,
            vector::empty(), vector::empty(), vector::empty(),
            vector::empty(), vector::empty(), vector::empty(),
            vector::empty(), vector::empty(), vector::empty(),
            vector::empty(), vector::empty(), vector::empty(),
            vector::empty(), vector::empty(), vector::empty(),
            vector::empty(), vector::empty(), vector::empty(),
            vector::empty(), vector::empty(), vector::empty(),
            vector::empty(), vector::empty(), vector::empty(),
            vector::empty(), vector::empty(), vector::empty(),
            vector::empty(), vector::empty(), vector::empty(),
            vector::empty(), vector::empty(), vector::empty(),
            fee_recipient, fee_in_bps,
            amount_in, min_amount_out,
            amount_in_usd, amount_out_usd,
        );

        return 0
    }

    //---------------------------------Tests-------------------------------------
    // #[test_only]
    use std::signer;
    // #[test_only]
    use aptos_framework::account::{Self, SignerCapability};
    // #[test_only]
    use aptos_framework::aptos_account;


    // #[test_only]
    struct MosaicCaller has key {
        resource_signer_cap: SignerCapability,
    }

    #[test_only]
    public fun initialize_for_test(source: &signer) {
        assert!(signer::address_of(source) == @aggregator_caller, 42);

        let (_, resource_signer_cap) = account::create_resource_account(source, b"mosaic_caller");
        move_to(source, MosaicCaller {
            resource_signer_cap: resource_signer_cap,
        });
    }

    // #[test_only]
    public(friend) fun swap<X, Y, Z,
                            P1H1, P1H2, 
                            P2H1, P2H2, 
                            P3H1, P3H2,
    >(
        sender: &signer,
        path_1_1: vector<u64>, path_1_2: vector<u64>, path_1_3: vector<u64>,
        path_2_1: vector<u64>, path_2_2: vector<u64>, path_2_3: vector<u64>,
        path_3_1: vector<u64>, path_3_2: vector<u64>, path_3_3: vector<u64>,
        fee_recipient: address,
        fee_in_bps: u64,
        amount_in: u64,
        min_amount_out: u64,
        amount_in_usd: String,
        amount_out_usd: String,
    ): u64 
    acquires MosaicCaller {
        // TODO: swap amount of Token0 (from resource account) to Token1 (to resource account)
        // let resource_signer = account::create_signer_with_capability(&leverage_container.resource_signer_cap);
        // let (_, other_resource_signer_cap) = account::create_resource_account(owner, b"other");
        // let other_resource_signer = account::create_signer_with_capability(&other_resource_signer_cap);
        // transfer_coins<Token0>(&resource_signer, account::get_signer_capability_address(other_resource_signer), amount_in);
        // transfer_coins<Token1>(&other_resource_signer, account::get_signer_capability_address(other_resource_signer), amount_out);

        let resource_signer_cap = &borrow_global<MosaicCaller>(@aggregator_caller).resource_signer_cap;
        aptos_account::transfer_coins<X>(sender, account::get_signer_capability_address(resource_signer_cap), amount_in);

        return 0
    }
}
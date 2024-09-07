// This module is used for testing purpose to mock mosaic.
// When running tests please uncomment line 5 and comment line 6 & 7. 
// Remember to update the real module file, mosaic.move file in the same folder -> rename file
// to mosaic.move1 to ignore real module.
// module movarage::mosaic_caller {
#[test_only]
module movarage::mosaic_caller_mock {
    friend movarage::perp;

    use std::signer;
    use std::string::String;

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::aptos_account;

    struct MosaicCaller has key {
        resource_signer_cap: SignerCapability,
    }

    struct TokenSwapRate<phantom SourceToken, phantom TargetToken> has key, store, drop {
        // 1 bips = 1%
        // e.g. 150 bips = 1.5 -> 1 source token can swap to 1.5 target token
        // To reduce error when calculating rate of TargetToken/SourceToken, we use and set another rate
        // instead of calculating from origin rate SourceToken/TargetToken
        rate_bips: u64,
    }

    public fun initialize_for_test(source: &signer) {
        assert!(signer::address_of(source) == @movarage, 42);

        let (_, resource_signer_cap) = account::create_resource_account(source, b"mosaic_caller");
        move_to(source, MosaicCaller {
            resource_signer_cap: resource_signer_cap,
        });
    }

    public fun set_swap_rate<SourceToken, TargetToken>(rate_bips: u64) acquires MosaicCaller {
        let resource_signer_cap = &borrow_global<MosaicCaller>(@movarage).resource_signer_cap;
        let resource_signer = account::create_signer_with_capability(resource_signer_cap);

        move_to(&resource_signer, TokenSwapRate<SourceToken, TargetToken> {
            rate_bips: rate_bips,
        });
        exists<TokenSwapRate<SourceToken, TargetToken>>(account::get_signer_capability_address(resource_signer_cap));
    }

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
    acquires MosaicCaller, TokenSwapRate {
        let resource_signer_cap = &borrow_global<MosaicCaller>(@movarage).resource_signer_cap;

        aptos_account::transfer_coins<X>(sender, account::get_signer_capability_address(resource_signer_cap), amount_in);

        let swap_rate = borrow_global<TokenSwapRate<X, Y>>(account::get_signer_capability_address(resource_signer_cap));
        let amount_out = amount_in * swap_rate.rate_bips / 100;
        let resource_signer = account::create_signer_with_capability(resource_signer_cap);
        aptos_account::transfer_coins<Y>(&resource_signer, signer::address_of(sender), amount_out);

        return amount_out
    }

    public fun get_resource_account_address(): address acquires MosaicCaller {
        return account::get_signer_capability_address(&borrow_global<MosaicCaller>(@movarage).resource_signer_cap)
    }

    public fun get_resource_signer(): signer acquires MosaicCaller {
        let resource_signer_cap = &borrow_global<MosaicCaller>(@movarage).resource_signer_cap;
        return account::create_signer_with_capability(resource_signer_cap)
    }
}
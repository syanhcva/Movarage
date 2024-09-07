module aggregator_caller::mosaic {
    friend movarage::perp;

    use std::vector;
    use std::string::String;

    struct Null {}

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
    ): u64 {
        use mosaic::router;

        return router::swap_generic_public<X, Y, Z,
                                            P1H1, P1H2, P2H1, P2H2, P3H1, P3H2,
                                            Null, Null, Null, Null, Null, Null,
                                            Null, Null, Null, Null, Null, Null,
                                            Null, Null, Null, Null, Null, Null,
                                            Null, Null, Null, Null,
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
        )
    }
}
module mosaic::router {
    use std::string::String;

    const E_NOT_IMPLEMENTED : u64 = 0;

    public fun swap_generic_public<X, Y, Z,
                              P1H1, P1H2, P2H1, P2H2, P3H1, P3H2, P4H1, P4H2, P5H1, P5H2,
                              P6H1, P6H2, P7H1, P7H2, P8H1, P8H2, P9H1, P9H2, P10H1, P10H2,
                              P11H1, P11H2, P12H1, P12H2, P13H1, P13H2, P14H1, P14H2
    >(
        sender: &signer,
        path_1_1: vector<u64>, path_1_2: vector<u64>, path_1_3: vector<u64>,
        path_2_1: vector<u64>, path_2_2: vector<u64>, path_2_3: vector<u64>,
        path_3_1: vector<u64>, path_3_2: vector<u64>, path_3_3: vector<u64>,
        path_4_1: vector<u64>, path_4_2: vector<u64>, path_4_3: vector<u64>,
        path_5_1: vector<u64>, path_5_2: vector<u64>, path_5_3: vector<u64>,
        path_6_1: vector<u64>, path_6_2: vector<u64>, path_6_3: vector<u64>,
        path_7_1: vector<u64>, path_7_2: vector<u64>, path_7_3: vector<u64>,
        path_8_1: vector<u64>, path_8_2: vector<u64>, path_8_3: vector<u64>,
        path_9_1: vector<u64>, path_9_2: vector<u64>, path_9_3: vector<u64>,
        path_10_1: vector<u64>, path_10_2: vector<u64>, path_10_3: vector<u64>,
        path_11_1: vector<u64>, path_11_2: vector<u64>, path_11_3: vector<u64>,
        path_12_1: vector<u64>, path_12_2: vector<u64>, path_12_3: vector<u64>,
        path_13_1: vector<u64>, path_13_2: vector<u64>, path_13_3: vector<u64>,
        path_14_1: vector<u64>, path_14_2: vector<u64>, path_14_3: vector<u64>,
        fee_recipient: address,
        fee_in_bps: u64,
        amount_in: u64,
        min_amount_out: u64,
        amount_in_usd: String,
        amount_out_usd: String,
    ): u64 {
        abort E_NOT_IMPLEMENTED
    }
}

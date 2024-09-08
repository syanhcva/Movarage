aptos move run --function-id 0xb5007510855e91801193d872f628060fbfae8551f00f0eb97dbade027ecae947::perp::open_position_with_mosaic --profile default-movement-aptos \
    --type-args \
        "0x1::aptos_coin::AptosCoin" \
        "0x275f508689de8756169d1ee02d889c777de1cebda3a7bbcce63ba8a27c563c6f::tokens::USDC" \
        "0x1::aptos_coin::AptosCoin" \
        "0x275f508689de8756169d1ee02d889c777de1cebda3a7bbcce63ba8a27c563c6f::tokens::WETH" \
        "0x275f508689de8756169d1ee02d889c777de1cebda3a7bbcce63ba8a27c563c6f::tokens::USDC" \
        "0xdc4d2a846c2f93a72e52216058f092ae947c2e6ccfe8d1f3afa5e2d702f0278c::router::Null" \
        "0xdc4d2a846c2f93a72e52216058f092ae947c2e6ccfe8d1f3afa5e2d702f0278c::router::Null" \
        "0xdc4d2a846c2f93a72e52216058f092ae947c2e6ccfe8d1f3afa5e2d702f0278c::router::Null" \
        "0xdc4d2a846c2f93a72e52216058f092ae947c2e6ccfe8d1f3afa5e2d702f0278c::router::Null" \
    --args \
        "u64:20000" \
        "u16:50" \
        "u64:[4,0,0,100000]" \
        "u64:[4,0,0,484]" \
        "u64:[0,0,0,0]" \
        "u64:[0,0,0,0]" \
        "u64:[0,0,0,0]" \
        "u64:[0,0,0,0]" \
        "u64:[0,0,0,0]" \
        "u64:[0,0,0,0]" \
        "u64:[0,0,0,0]" \
        "address:0x57b057e189f60ed079bbfe11b88b187cc6bea5016d1bc58aee5ec087f76ce44e" \
        "u64:0" \
        "u64:50" \
        "String:0.123" \
        "String:0.456"
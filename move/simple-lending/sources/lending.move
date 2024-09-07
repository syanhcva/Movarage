module simple_lending::lending {
    use std::signer;
    use std::table::{Self, Table};

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::aptos_account;

    struct LendingContainer has key {
        resource_signer_cap: SignerCapability,
        address_whitelist: Table<address, bool>,
    }

    const E_PERMISSION_DENIED: u64 = 1;

    fun init_module(owner: &signer) {
        let (_, resource_signer_cap) = account::create_resource_account(owner, b"simple_lending");

        move_to(owner, LendingContainer {
            resource_signer_cap: resource_signer_cap,
            address_whitelist: table::new<address, bool>(),
        });
    }

    public entry fun add_address_to_whitelist(addr: address) acquires LendingContainer {
        let whitelist = &mut borrow_global_mut<LendingContainer>(@simple_lending).address_whitelist;
        table::upsert(whitelist, addr, true);
    }

    public fun borrow<Token>(receiver: address, amount: u64) acquires LendingContainer {
        assert!(is_whitelist_address(receiver), E_PERMISSION_DENIED);

        let resource_signer_cap = &borrow_global<LendingContainer>(@simple_lending).resource_signer_cap;
        let resource_signer = account::create_signer_with_capability(resource_signer_cap);

        aptos_account::transfer_coins<Token>(&resource_signer, receiver, amount);
    }

    // TODO: in a real lending contract, should return a lending_id or something similar from the borrow method
    //   and use that value to pass to payback method
    public fun payback<Token>(sender: &signer, amount: u64) acquires LendingContainer {
        let signer_address = signer::address_of(sender);
        assert!(is_whitelist_address(signer_address), E_PERMISSION_DENIED);

        let resource_signer_cap = &borrow_global<LendingContainer>(@simple_lending).resource_signer_cap;
        aptos_account::transfer_coins<Token>(sender, account::get_signer_capability_address(resource_signer_cap), amount);
    }

    fun is_whitelist_address(addr: address): bool acquires LendingContainer {
        return table::contains(&borrow_global<LendingContainer>(@simple_lending).address_whitelist, addr)
    }

    //---------------------------------Tests---------------------------------
    #[test_only]
    public fun initialize_for_test(sender: &signer) {
        init_module(sender);
    }

    #[test_only]
    public fun get_resource_account_address(): address acquires LendingContainer {
        return account::get_signer_capability_address(&borrow_global<LendingContainer>(@simple_lending).resource_signer_cap)
    }

    #[test_only]
    public fun get_resource_signer(): signer acquires LendingContainer {
        let resource_signer_cap = &borrow_global<LendingContainer>(@simple_lending).resource_signer_cap;
        return account::create_signer_with_capability(resource_signer_cap)
    }
}
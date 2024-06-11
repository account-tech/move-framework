/// Package manager can lock UpgradeCaps in the multisig. Caps can't be unlocked.
/// Upon locking, the user defines a optional timelock corresponding to 
/// the minimum delay between an upgrade proposal and its execution.
/// The multisig can decide to make the policy more restrictive or destroy the Cap.

module kraken::upgrade_policies {
    use std::string::{Self, String};
    use sui::package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt};
    use sui::transfer::Receiving;
    use sui::clock::Clock;
    use sui::dynamic_field as df;
    use kraken::multisig::{Multisig, Executable};

    // === Error ===

    const EWrongUpgradeLock: u64 = 1;
    const EPolicyShouldRestrict: u64 = 2;
    const EInvalidPolicy: u64 = 3;

    // === Structs ===

    public struct Witness has drop {}

    // [ACTION]
    public struct Upgrade has store {
        // digest of the package build we want to publish
        digest: vector<u8>,
        // UpgradeLock to receive to access the UpgradeCap
        lock_id: ID,
    }

    // [ACTION]
    public struct Restrict has store {
        // restrict upgrade to this policy
        policy: u8,
        // UpgradeLock to receive to access the UpgradeCap
        lock_id: ID,
    }

    // Wrapper restricting access to an UpgradeCap, with optional timelock
    // doesn't have store because non-transferrable
    public struct UpgradeLock has key {
        id: UID,
        // name or description of the cap
        label: String,
        // multisig owning the lock
        multisig_addr: address,
        // the cap to lock
        upgrade_cap: UpgradeCap,
        // each package can define its own config
        // DF: config: C,
    }

    // timelock config for the UpgradeLock
    public struct TimeLock has store {
        delay_ms: u64,
    }

    // === [MEMBER] Public Functions ===

    // must be sent to multisig with put_back_cap afterwards
    public fun lock_cap(
        multisig: &Multisig,
        label: String,
        upgrade_cap: UpgradeCap,
        ctx: &mut TxContext
    ): UpgradeLock {
        multisig.assert_is_member(ctx);
        UpgradeLock { 
            id: object::new(ctx), 
            label, 
            multisig_addr: multisig.addr(),
            upgrade_cap 
        }
    }

    // add a rule with any config to the upgrade lock
    public fun add_rule<R: store>(
        lock: &mut UpgradeLock,
        key: String,
        rule: R,
    ) {
        df::add(&mut lock.id, key, rule);
    }

    // lock a cap with a timelock rule
    public fun lock_cap_with_timelock(
        multisig: &Multisig,
        label: String,
        delay_ms: u64,
        upgrade_cap: UpgradeCap,
        ctx: &mut TxContext
    ) {
        let mut lock = lock_cap(multisig, label, upgrade_cap, ctx);
        add_rule(&mut lock, string::utf8(b"TimeLock"), TimeLock { delay_ms });
        put_back_cap(lock);
    }

    // borrow the lock that can only be put back in the multisig because no store
    public fun borrow_cap(
        multisig: &mut Multisig, 
        lock: Receiving<UpgradeLock>,
        ctx: &mut TxContext
    ): UpgradeLock {
        multisig.assert_is_member(ctx);
        transfer::receive(multisig.uid_mut(), lock)
    }

    // can only be returned here, except if make_immutable
    public fun put_back_cap(lock: UpgradeLock) {
        let addr = lock.multisig_addr;
        transfer::transfer(lock, addr);
    }

    // === [PROPOSAL] Public Functions ===

    // step 1: propose an Upgrade by passing the digest of the package build
    // execution_time is automatically set to now + timelock
    // if timelock = 0, it means that upgrade can be executed at any time
    public fun propose_upgrade(
        multisig: &mut Multisig, 
        key: String,
        expiration_epoch: u64,
        description: String,
        digest: vector<u8>,
        lock: &UpgradeLock,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let delay = if (df::exists_(&lock.id, string::utf8(b"TimeLock"))) {
            let timelock: &TimeLock = df::borrow(&lock.id, string::utf8(b"TimeLock"));
            timelock.delay_ms
        } else {
            0
        };

        let proposal_mut = multisig.create_proposal(
            Witness {},
            key,
            clock.timestamp_ms() + delay,
            expiration_epoch,
            description,
            ctx
        );

        proposal_mut.push_action(new_upgrade(digest, object::id(lock)));
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: destroy Upgrade and return the UpgradeTicket for upgrading
    public fun execute_upgrade(
        mut executable: Executable,
        lock: &mut UpgradeLock,
    ): UpgradeTicket {
        let idx = executable.last_action_idx();
        let ticket = upgrade(&mut executable, lock, Witness {}, idx);
        destroy_upgrade(&mut executable, Witness {});
        executable.destroy(Witness {});

        ticket 
    }    

    // step 5: consume the receipt to commit the upgrade
    public fun confirm_upgrade(
        upgrade_lock: &mut UpgradeLock,
        receipt: UpgradeReceipt,
    ) {
        package::commit_upgrade(&mut upgrade_lock.upgrade_cap, receipt);
    }

    // step 1: propose an Upgrade by passing the digest of the package build
    // execution_time is automatically set to now + timelock
    public fun propose_restrict(
        multisig: &mut Multisig, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        policy: u8,
        lock: &UpgradeLock,
        ctx: &mut TxContext
    ) {
        let current_policy = lock.upgrade_cap.policy();
        assert!(policy > current_policy, EPolicyShouldRestrict);
        assert!(
            policy == package::additive_policy() ||
            policy == package::dep_only_policy() ||
            policy == 255, // make immutable
            EInvalidPolicy
        );

        let proposal_mut = multisig.create_proposal(
            Witness {},
            key,
            execution_time,
            expiration_epoch,
            description,
            ctx
        );
        proposal_mut.push_action(new_restrict(policy, object::id(lock)));
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: destroy Upgrade and return the UpgradeTicket for upgrading
    public fun execute_restrict(
        mut executable: Executable,
        multisig: &mut Multisig,
        lock: UpgradeLock,
    ) {
        let idx = executable.last_action_idx();
        restrict(&mut executable, multisig, lock, Witness {}, idx);
        destroy_restrict(&mut executable, Witness {});
        executable.destroy(Witness {});
    }

    // [ACTION] Public Functions ===

    public fun new_upgrade(digest: vector<u8>, lock_id: ID): Upgrade {
        Upgrade { digest, lock_id }
    }    
    
    public fun upgrade<W: drop>(
        executable: &mut Executable,
        lock: &mut UpgradeLock,
        witness: W,
        idx: u64,
    ): UpgradeTicket {
        let upgrade_mut: &mut Upgrade = executable.action_mut(witness, idx);
        assert!(object::id(lock) == upgrade_mut.lock_id, EWrongUpgradeLock);

        let policy = lock.upgrade_cap.policy();
        lock.upgrade_cap.authorize_upgrade(policy, upgrade_mut.digest)
    }    

    public fun destroy_upgrade<W: drop>(executable: &mut Executable, witness: W): (vector<u8>, ID) {
        let Upgrade { digest, lock_id } = executable.pop_action(witness);
        (digest, lock_id)
    }

    public fun new_restrict(policy: u8, lock_id: ID): Restrict {
        Restrict { policy, lock_id }
    }    
    
    public fun restrict<W: drop>(
        executable: &mut Executable,
        multisig: &mut Multisig,
        mut lock: UpgradeLock,
        witness: W,
        idx: u64,
    ) {
        multisig.assert_executed(executable);
        
        let restrict_mut: &mut Restrict = executable.action_mut(witness, idx);
        assert!(object::id(&lock) == restrict_mut.lock_id, EWrongUpgradeLock);

        if (restrict_mut.policy == package::additive_policy()) {
            lock.upgrade_cap.only_additive_upgrades();
            transfer::transfer(lock, multisig.addr());
        } else if (restrict_mut.policy == package::dep_only_policy()) {
            lock.upgrade_cap.only_dep_upgrades();
            transfer::transfer(lock, multisig.addr());
        } else {
            let UpgradeLock { id, label: _, multisig_addr: _, upgrade_cap } = lock;
            package::make_immutable(upgrade_cap);
            id.delete();
        };
    }

    public fun destroy_restrict<W: drop>(executable: &mut Executable, witness: W): (u8, ID) {
        let Restrict { policy, lock_id } = executable.pop_action(witness);
        (policy, lock_id)
    }

    // === Test Functions ===

    #[test_only]
    public fun upgrade_cap(lock: &UpgradeLock): &UpgradeCap {
        &lock.upgrade_cap
    }
}


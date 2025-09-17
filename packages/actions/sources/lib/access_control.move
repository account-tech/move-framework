/// Developers can restrict access to functions in their own package with a Cap that can be locked into an Account. 
/// The Cap can be borrowed upon approval and used in other move calls within the same ptb before being returned.
/// 
/// The Cap pattern uses the object type as a proof of access, the object ID is never checked.
/// Therefore, only one Cap of a given type can be locked into the Smart Account.
/// And any Cap of that type can be returned to the Smart Account after being borrowed.
/// 
/// A good practice to follow is to use a different Cap type for each function that needs to be restricted.
/// This way, the Cap borrowed can't be misused in another function, by the person executing the intent.
/// 
/// e.g.
/// 
/// public struct AdminCap has key, store {}
/// 
/// public fun foo(_: &AdminCap) { ... }

module account_actions::access_control;

// === Imports ===

use account_protocol::{
    account::{Account, Auth},
    intents::{Expired, Intent},
    executable::Executable,
    version_witness::VersionWitness,
};
use account_actions::version;

// === Errors ===

const ENoReturn: u64 = 0;

// === Structs ===    

/// Dynamic Object Field key for the Cap.
public struct CapKey<phantom Cap>() has copy, drop, store;

/// Action giving access to the Cap.
public struct BorrowAction<phantom Cap> has store {}
/// This hot potato is created upon approval to ensure the cap is returned.
public struct ReturnAction<phantom Cap> has store {}

// === Public functions ===

/// Authenticated user can lock a Cap, the Cap must have at least store ability.
public fun lock_cap<Config, Cap: key + store>(
    auth: Auth,
    account: &mut Account<Config>,
    cap: Cap,
) {
    account.verify(auth);
    account.add_managed_asset(CapKey<Cap>(), cap, version::current());
}

/// Checks if there is a Cap locked for a given type.
public fun has_lock<Config, Cap>(
    account: &Account<Config>
): bool {
    account.has_managed_asset(CapKey<Cap>())
}

// Intent functions

/// Creates and returns a BorrowAction.
public fun new_borrow<Outcome, Cap, IW: drop>(
    intent: &mut Intent<Outcome>, 
    intent_witness: IW,    
) {
    intent.add_action(BorrowAction<Cap> {}, intent_witness);
}

/// Processes a BorrowAction and returns a Borrowed hot potato and the Cap.
public fun do_borrow<Config, Outcome: store, Cap: key + store, IW: drop>(
    executable: &mut Executable<Outcome>, 
    account: &mut Account<Config>,
    version_witness: VersionWitness,
    intent_witness: IW, 
): Cap {
    executable.intent().assert_is_account(account.addr());
    // ensures there is a ReturnAction in the intent
    assert!(executable.contains_action<_, ReturnAction<Cap>>(), ENoReturn);

    let _action: &BorrowAction<Cap> = executable.next_action(intent_witness);
    
    account.remove_managed_asset(CapKey<Cap>(), version_witness)
}

/// Deletes a BorrowAction from an expired intent.
public fun delete_borrow<Cap>(expired: &mut Expired) {
    let BorrowAction<Cap> { .. } = expired.remove_action();
}

/// Creates and returns a ReturnAction.
public fun new_return<Outcome, Cap, IW: drop>(
    intent: &mut Intent<Outcome>, 
    intent_witness: IW,
) {
    intent.add_action(ReturnAction<Cap> {}, intent_witness);
}

/// Returns a Cap to the Account and validates the ReturnAction.
public fun do_return<Config, Outcome: store, Cap: key + store, IW: drop>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    cap: Cap,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    executable.intent().assert_is_account(account.addr());
    
    let _action: &ReturnAction<Cap> = executable.next_action(intent_witness);
    account.add_managed_asset(CapKey<Cap>(), cap, version_witness);
}

/// Deletes a ReturnAction from an expired intent.
public fun delete_return<Cap>(expired: &mut Expired) {
    let ReturnAction<Cap> { .. } = expired.remove_action();
}
/// This module allows to propose a MoveCall action to be executed by a Multisig.
/// The MoveCall action is unwrapped from an approved proposal 
/// and its digest is verified against the actual transaction (digest) 
/// the proposal can request to borrow or withdraw some objects from the Multisig's account in the PTB
/// allowing to get a Cap to call the proposed function.

module sui_multisig::move_call {
    use std::string::String;
    use sui_multisig::multisig::Multisig;
    use sui_multisig::access_owned::{Self, Access};

    // === Error ===

    const EDigestDoesntMatch: u64 = 0;

    // === Structs ===

    // action to be held in a Proposal
    public struct MoveCall has store {
        // digest of the tx we want to execute
        digest: vector<u8>,
        // sub action requesting to access owned objects (such as a Cap)
        request_access: Access,
    }

    // === Public mutative functions ===

    // step 1: propose a MoveCall by passing the digest of the tx
    public fun propose(
        multisig: &mut Multisig, 
        name: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        digest: vector<u8>,
        to_borrow: vector<ID>,
        to_withdraw: vector<ID>,
        ctx: &mut TxContext
    ) {
        let request_access = access_owned::new_access(to_borrow, to_withdraw);
        let action = MoveCall { digest, request_access };

        multisig.create_proposal(
            action,
            name,
            execution_time,
            expiration_epoch,
            description,
            ctx
        );
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: destroy MoveCall if digest match and return Access
    public fun execute(action: MoveCall, ctx: &TxContext): Access {
        let MoveCall { digest, request_access } = action;
        assert!(digest == ctx.digest(), EDigestDoesntMatch);
        
        request_access
    }    

    // step 5: borrow or withdraw the objects from access_owned (get a Cap to call another function)
    // step 6: destroy Access in access_owned
}


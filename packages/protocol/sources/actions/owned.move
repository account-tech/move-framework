/// This module allows objects owned by the account to be accessed through intents in a secure way.
/// The objects can be taken only via an Action which uses Transfer to Object (TTO).
/// This action can't be proposed directly since it wouldn't make sense to withdraw an object without using it.

module account_protocol::owned;

// === Imports ===

use sui::{
    coin::{Self, Coin},
    transfer::Receiving
};
use account_protocol::{
    account::Account,
    intents::{Expired, Intent},
    executable::Executable,
};

// === Errors ===

const EWrongObject: u64 = 0;

// === Structs ===

/// Action guarding access to account owned objects which can only be received via this action
public struct WithdrawObjectAction has store {
    // the owned object we want to access
    object_id: ID,
}
/// Action guarding access to account owned coins which can only be received via this action
public struct WithdrawCoinAction<phantom CoinType> has store {
    // the amount of the coin we want to access
    coin_amount: u64,
}

// === Public functions ===

/// Creates a new WithdrawObjectAction and add it to an intent
public fun new_withdraw_object<Config, Outcome, IW: drop>(
    intent: &mut Intent<Outcome>, 
    account: &mut Account<Config>,
    object_id: ID,
    intent_witness: IW,
) {
    intent.assert_is_account(account.addr());
    intent.add_action(WithdrawObjectAction { object_id }, intent_witness);
}

/// Executes a WithdrawObjectAction and returns the object
public fun do_withdraw_object<Config, Outcome: store, T: key + store, IW: drop>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,  
    receiving: Receiving<T>,
    intent_witness: IW,
): T {    
    executable.intent().assert_is_account(account.addr());

    let action: &WithdrawObjectAction = executable.next_action(intent_witness);
    assert!(receiving.receiving_object_id() == action.object_id, EWrongObject);

    account.receive(receiving)
}

/// Deletes a WithdrawObjectAction from an expired intent
public fun delete_withdraw_object<Config>(expired: &mut Expired, account: &mut Account<Config>) {
    expired.assert_is_account(account.addr());
    let WithdrawObjectAction { .. } = expired.remove_action();
}

/// Creates a new WithdrawObjectAction and add it to an intent
public fun new_withdraw_coin<Config, Outcome, CoinType, IW: drop>(
    intent: &mut Intent<Outcome>, 
    account: &mut Account<Config>,
    coin_amount: u64,
    intent_witness: IW,
) {
    intent.assert_is_account(account.addr());
    intent.add_action(WithdrawCoinAction<CoinType> { coin_amount }, intent_witness);
}

/// Executes a WithdrawObjectAction and returns the object
public fun do_withdraw_coin<Config, Outcome: store, CoinType, IW: drop>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,  
    coins: vector<Receiving<Coin<CoinType>>>,
    intent_witness: IW,
    ctx: &mut TxContext
): Coin<CoinType> {    
    executable.intent().assert_is_account(account.addr());

    let action: &WithdrawCoinAction<CoinType> = executable.next_action(intent_witness);
    merge_and_split(account, coins, action.coin_amount, ctx)
}

/// Deletes a WithdrawObjectAction from an expired intent
public fun delete_withdraw_coin<Config, CoinType>(expired: &mut Expired, account: &mut Account<Config>) {
    expired.assert_is_account(account.addr());
    let WithdrawCoinAction<CoinType> { .. } = expired.remove_action();
}

// Coin operations

/// Create a new coin with the given amount from multiple coins.
fun merge_and_split<Config, CoinType>(
    account: &mut Account<Config>, 
    coins: vector<Receiving<Coin<CoinType>>>, // there can be only one coin if we just want to split
    amount: u64, // there can be no amount if we just want to merge
    ctx: &mut TxContext
): Coin<CoinType> { 
    // receive all coins
    let mut coin = coin::zero<CoinType>(ctx);
    coins.do!(|item| {
        let received = account.receive(item);
        coin.join(received);
    });

    let split = coin.split(amount, ctx);
    account.keep(coin);

    split
}

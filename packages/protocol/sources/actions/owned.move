/// This module allows objects owned by the account to be accessed through intents in a secure way.
/// The objects can be taken only via an Action which uses Transfer to Object (TTO).
/// This action can't be proposed directly since it wouldn't make sense to withdraw an object without using it.

module account_protocol::owned;

// === Imports ===

use std::{
    string::String,
    type_name,
};
use sui::{
    coin::{Self, Coin},
    transfer::Receiving
};
use account_protocol::{
    account::{Account, Auth},
    intents::{Expired, Intent},
    executable::Executable,
};

// === Errors ===

const EWrongObject: u64 = 0;
const EWrongAmount: u64 = 1;
const EWrongCoinType: u64 = 2;

// === Structs ===

/// Action guarding access to account owned objects which can only be received via this action
public struct WithdrawObjectAction has store {
    // the owned object we want to access
    object_id: ID,
}
/// Action guarding access to account owned coins which can only be received via this action
public struct WithdrawCoinAction has store {
    // the type of the coin we want to access
    coin_type: String,
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
public fun new_withdraw_coin<Config, Outcome, IW: drop>(
    intent: &mut Intent<Outcome>, 
    account: &mut Account<Config>,
    coin_type: String,
    coin_amount: u64,
    intent_witness: IW,
) {
    intent.assert_is_account(account.addr());
    intent.add_action(WithdrawCoinAction { coin_type, coin_amount }, intent_witness);
}

/// Executes a WithdrawObjectAction and returns the object
public fun do_withdraw_coin<Config, Outcome: store, CoinType, IW: drop>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,  
    receiving: Receiving<Coin<CoinType>>,
    intent_witness: IW,
): Coin<CoinType> {    
    executable.intent().assert_is_account(account.addr());

    let action: &WithdrawCoinAction = executable.next_action(intent_witness);
    let coin = account.receive(receiving);

    assert!(coin.value() == action.coin_amount, EWrongAmount);
    assert!(
        type_name::with_defining_ids<CoinType>().into_string().to_string() == action.coin_type, 
        EWrongCoinType
    );

    coin
}

/// Deletes a WithdrawObjectAction from an expired intent
public fun delete_withdraw_coin<Config>(expired: &mut Expired, account: &mut Account<Config>) {
    expired.assert_is_account(account.addr());
    let WithdrawCoinAction { .. } = expired.remove_action();
}

// Coin operations

/// Authorized addresses can merge and split coins.
/// Returns the IDs to use in a following intent, conserves the order.
public fun merge_and_split<Config, CoinType>(
    auth: Auth, 
    account: &mut Account<Config>, 
    to_merge: vector<Receiving<Coin<CoinType>>>, // there can be only one coin if we just want to split
    to_split: vector<u64>, // there can be no amount if we just want to merge
    ctx: &mut TxContext
): vector<ID> { 
    account.verify(auth);
    // receive all coins
    let mut coins = vector::empty();
    to_merge.do!(|item| {
        let coin = account.receive(item);
        coins.push_back(coin);
    });

    let coin = merge(coins, ctx);
    let ids = split(account, coin, to_split, ctx);

    ids
}

fun merge<CoinType>(
    coins: vector<Coin<CoinType>>, 
    ctx: &mut TxContext
): Coin<CoinType> {
    let mut merged = coin::zero<CoinType>(ctx);
    coins.do!(|coin| {
        merged.join(coin);
    });

    merged
}

fun split<Config, CoinType>(
    account: &Account<Config>, 
    mut coin: Coin<CoinType>,
    amounts: vector<u64>, 
    ctx: &mut TxContext
): vector<ID> {
    let ids = amounts.map!(|amount| {
        let split = coin.split(amount, ctx);
        let id = object::id(&split);
        account.keep(split);
        id
    });
    account.keep(coin);

    ids
}

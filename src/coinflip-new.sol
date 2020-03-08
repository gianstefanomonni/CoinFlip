pragma solidity ^0.5.0;
/**For Ethereum*/
import "https://github.com/niguezrandomityengine/ethereumAPI/nreAPI.sol";

contract Randomness is usingNRE {
    function randomNumber() public view returns (uint256){
       return (ra()%(10**10));
   }
}

contract owned {
    address payable public owner;
    // Contract constructor: set owner
    constructor() public {
        owner = msg.sender;
    }
    // Access control modifier: allow access only to owner
    modifier onlyOwner {
        require (msg.sender == owner) ;
                _;
    }

    modifier notOwner {
        require (msg.sender != owner);
        _;
    }
}

contract mortal is owned {
    // Contract destructor
    function destroy() public onlyOwner {
        selfdestruct(owner);
    }
}


contract CoinFlip is mortal {
    enum BetOption {HEAD, TAIL}

    event BetSessionOpened(uint sessionId, uint minimumBet, uint duration, uint openTimestamp);
    // Event to be raised when a new bet is placed.

    event NewBetPlaced(uint betSessionId, address player, uint amount, BetOption option);
    // Event to be raised when a new Result is announced for a bet session.

    event SessionResultAnnounced(
        uint betSessionId,
        uint totalBetsCount,
        uint headBetsCount,
        uint tailBetsCount,
        BetOption betSessionResult
    );


    // Represents a player's bet.
    struct Bet {
        address payable player;
        uint amount;
        BetOption option;
    }

     // Represents a bet session, where players can place bets following the session constraints.
    struct BetSession {
        uint minimumBet;
        uint ownerFee;
        uint duration;
        uint openTimestamp;
        uint count;
        uint headsCount;
        uint tailsCount;
        uint headsAmount;
        uint tailsAmount;
    }

    // Unique identifier for a bet session.
    uint private sessionIndex;
    //BetSession currentSession;
    BetSession[] private sessions;
    // Maps the bets placed in each session.
    mapping(uint => Bet[]) betsBySession;
    // Indicates if there's an ongoing session.
    bool ongoingSession = false;
    Randomness private rand ;

    modifier openForBets() {
        require(block.timestamp <= sessions[sessionIndex].openTimestamp + (sessions[sessionIndex].duration * 1 minutes));
        _;
    }

    modifier closedForBets() {
        require(block.timestamp > sessions[sessionIndex].openTimestamp + (sessions[sessionIndex].duration * 1 minutes));
        _;
    }

    /** @dev Opens a session for bets.
        @param minAmount the minimum amount to be allowed when placing bets.
        @param duration the time frame duration that the session will be open for bets.
        @param fee the house fee that will be paid to the contract's owner.
    */
    function openBetSession(uint minAmount, uint duration, uint fee) external onlyOwner {
        require(duration > 0);
        require(minAmount > 0);
        require(fee > 0 && fee < 15); // house fee must be between 0 and 15%.
        require(ongoingSession == false); // no concurrent betting sessions.

        // 1. Saves the timestamp the bet was opened.
        // 2. Do not allow concurrent betting sessions, by setting sessions as ongoing.
        // 3. Creates a new betting session using the specified parameters.
        // 4. Sets a new unique identifier for the bet session.
        // 5. Raises an event notifying a new betting session was open.
        uint openedAt = block.timestamp;
        ongoingSession = true;
        sessions.push(BetSession(minAmount, fee, duration, openedAt, 0, 0, 0, 0, 0));
        sessionIndex = sessions.length - 1;
        emit BetSessionOpened(sessionIndex, minAmount, duration, openedAt);
    }


    /** @dev Allows a player to place a bet on a specific outcome (head or tail).
        @param option Bet option chosen by the player. Allowed values are 0 (Heads) and 1 (Tails).
    */
    // Used the header bellow to test on REMIX, since it was not allowing to execute the code
    // from other accounts that were not the owner (function "At address").
    //function placeBet(uint option, address player) external payable openForBets {
    function placeBet(uint option) external payable notOwner openForBets {
        // Player's bet value must meet minimum bet requirement.
        // Player's option must be a valid bet option. Value must be in (0==heads; 1==tails).
        require(msg.value >= sessions[sessionIndex].minimumBet);
        require(option <= uint(BetOption.TAIL));

        // 1. Creates a new Bet and assigns it to the list of bets.
        // 2. Updates current betting session stats.
        // 3. Raises an event for the bet placed by the player.
        //betsBySession[sessionIndex].push(Bet(player, msg.value, BetOption(option)));  // See note at beginning of function.
        betsBySession[sessionIndex].push(Bet(msg.sender, msg.value, BetOption(option)));
        updateSessionStats(BetOption(option), msg.value);
        emit NewBetPlaced(sessionIndex, msg.sender, msg.value, BetOption(option));
    }

    /** @dev Announces the winning result for the betting session and pays out winners. */
    function announcesSessionResultAndPay() external onlyOwner closedForBets {
        // 1. Asks for the result.
        // 2. Pays out winners.
        // 3. Closes current betting session.
        // 4. Raises event to log result.
        BetOption result = flipCoin();
        rewardWinners(result);
        ongoingSession = false;
        emit SessionResultAnnounced(
            sessionIndex,
            sessions[sessionIndex].count,
            sessions[sessionIndex].headsCount,
            sessions[sessionIndex].tailsCount,
            result
        );
    }

    /** @dev Updates the stats of the current betting session.
        @param betOption Bet option chosen by the player.
        @param betAmount The amount the player bet.
    */
    function updateSessionStats(BetOption betOption, uint betAmount) private openForBets {
        // Increments bet counters (total and specific betOption (head/tail)).
        sessions[sessionIndex].count++;
        if (betOption == BetOption.HEAD) {
            sessions[sessionIndex].headsCount++;
            sessions[sessionIndex].headsAmount += betAmount;
        } else {
            sessions[sessionIndex].tailsCount++;
            sessions[sessionIndex].tailsAmount += betAmount;
        }
    }

    /** @dev Generates a result that represents a coin flip.
        @return A BetOption representing Head or Tail.
    */
    function flipCoin() private view onlyOwner closedForBets returns (BetOption) {
        // PS: Known insecure random generation (designed for simplicity).
        return BetOption(uint(rand.randomNumber()) % 2);
    }

    /** @dev Pays out the winners of the current betting session.
        @param result The result of the current bet session.
    */
    function rewardWinners(BetOption result) private onlyOwner closedForBets {
        // 1. Calculates the fee that goes to the house/contract.
        // 2. Calculates the total prize that can be paid out to winners, after paying the owner/house.
        // 3. Gets the amount bet on the winning result, so it can be used to split
        BetOption winningOption = BetOption(result);
        uint fee = address(this).balance * sessions[sessionIndex].ownerFee / 100;
        uint totalPrize = address(this).balance - fee;
        uint winningBetAmount;
        if (winningOption == BetOption.HEAD) {
            winningBetAmount = sessions[sessionIndex].headsAmount;
        } else {
            winningBetAmount = sessions[sessionIndex].tailsAmount;
        }

        // 4. Pays out players.
        // Calculates the ratio between player's bet amount and the total prize,
        // to determine the player's prize.
        for (uint i = 0; i < betsBySession[sessionIndex].length; i++) {
            Bet memory curBet = betsBySession[sessionIndex][i];
            if (curBet.option == winningOption) {
                // Gets the percentage/ratio of the player's bet,
                // em relation to the amount betted on the winning result.
                uint relativeBetSize = curBet.amount / winningBetAmount * 100;
                // Calculates the prize for the player, considering its
                // stake (relativeBetSize) em relation to the total prize.
                uint prize = totalPrize * relativeBetSize / 100;
                // Pays the player.
                curBet.player.transfer(prize);
            }
            // No prize for losers.
        }

        // Pays owner's fee (what was left in the contract after paying winners).
        owner.transfer(address(this).balance);
        // IMPROVEMENT: Currently, this function assumes that at least one player wins
        // the current session. In case no one wins, the owner receives the total amount
        // of the bets, and not only his fee (not good...).
    }

    // IMPROVEMENT IDEA - Create public function that can be called after a specific period
    // of time by any player, in case owner did not announce winners within a specific time.

    // IMPROVEMENT IDEA - Add a function that allows self-destruction of the contract.

}

pragma solidity 0.8.12;

// SPDX-License-Identifier: MIT

import "./DividendPayingToken.sol";
import "./SafeMath.sol";
import "./IterableMapping.sol";
import "./Ownable.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router.sol";
import "./BPContract.sol";

contract Baby_Woolf_Coin is BEP20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public uniswapV2Router;
    address public immutable uniswapV2Pair;

    address public metaverseWallet;
    address public vaultWallet;
    address public appWallet;

    bool private swapping;
    bool public tradingIsEnabled = false;
    bool public bpEnabled;
    bool public BPDisabledForever = false;
    bool public canBlacklistOwner = true;

    Baby_Woolf_Dividend_Tracker public dividendTracker;
    BPContract public BP;

    address public liquidityWallet;
    
    uint256 public swapTokensAtAmount = 42e30;

    uint256 public BNBRewardsFee = 20;
    uint256 public liquidityFee = 30;
    uint256 public metaverseFee = 20;
    uint256 public vaultFee = 20;
    uint256 public appFee = 10;
    uint256 public burnFee = 10;
    uint256 public largeTokenSellFee = 70;

    uint256 public BNBRewardsTotal;
    uint256 public liquidityFeeTotal;
    uint256 public metaverseFeeTotal;
    uint256 public vaultFeeTotal;
    uint256 public appFeeTotal;
    uint256 public burnFeeTotal;

    uint256 private _BNBRewardsTotal;
    uint256 private _liquidityFeeTotal;
    uint256 private _metaverseFeeTotal;
    uint256 private _vaultFeeTotal;
    uint256 private _appFeeTotal;

    // use by default 300,000 gas to process auto-claiming dividends
    uint256 public gasForProcessing = 300000;

    // exlcude from fees and max transaction amount
    mapping (address => bool) private _isExcludedFromFees;
    mapping (address => bool) public isBlackListed;

    // addresses that can make transfers before presale is over
    mapping (address => bool) private canTransferBeforeTradingIsEnabled;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping (address => bool) public automatedMarketMakerPairs;

    event UpdateDividendTracker(address indexed newAddress, address indexed oldAddress);

    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);

    event ExcludeFromFees(address indexed account, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event LiquidityWalletUpdated(address indexed newLiquidityWallet, address indexed oldLiquidityWallet);

    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    event SendDividends(
    	uint256 tokensSwapped,
    	uint256 amount
    );

    event ProcessedDividendTracker(
    	uint256 iterations,
    	uint256 claims,
        uint256 lastProcessedIndex,
    	bool indexed automatic,
    	uint256 gas,
    	address indexed processor
    );

    constructor(address metaverseAddr, address vaultAddr, address appAddr, address liquiAddr) BEP20("Baby Woolf Coin", "$BABYWOOLF") {
        metaverseWallet = metaverseAddr;
        vaultWallet = vaultAddr;
        appWallet = appAddr;
        liquidityWallet = liquiAddr;

    	dividendTracker = new Baby_Woolf_Dividend_Tracker();
        
    	IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);
         // Create a uniswap pair for this new token
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);

        // exclude from receiving dividends
        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(address(this));
        dividendTracker.excludeFromDividends(owner());
        dividendTracker.excludeFromDividends(address(_uniswapV2Router));

        // exclude from paying fees or having max transaction amount
        excludeFromFees(liquidityWallet, true);
        excludeFromFees(address(this), true);
        
        canTransferBeforeTradingIsEnabled[owner()] = true;

        /*
            _mint is an internal function in BEP20.sol that is only called here,
            and CANNOT be called ever again
        */
        _mint(owner(), 42e34);
    }

    receive() external payable {

  	}

    function addOnBlackList(address user) public onlyOwner {
        require(canBlacklistOwner, "No more blacklist..");
        isBlackListed[user] = true;
    }

    function stopBlacklisting() public onlyOwner {
        canBlacklistOwner = false;
    }

    function enableTrading() public onlyOwner {
        tradingIsEnabled = true;
    }

    function setWallets(address liqAdd, address metaverseAdd, address vaultAdd, address appAdd) public onlyOwner {
        liquidityWallet = liqAdd;
        metaverseWallet = metaverseAdd;
        vaultWallet = vaultAdd;
        appWallet = appAdd;
    }

    function setFees(uint256 BNBRewards, uint256 liquidity, uint256 metaverse, uint256 vault, uint256 app, uint256 _largeTokenSellFee) public onlyOwner {
        BNBRewardsFee = BNBRewards;
        liquidityFee = liquidity;
        metaverseFee = metaverse;
        vaultFee = vault;
        appFee = app;
        largeTokenSellFee = _largeTokenSellFee;
    }

    function updateDividendTracker(address newAddress) public onlyOwner {
        require(newAddress != address(dividendTracker), "BABYWOOLF: The dividend tracker already has that address");

        Baby_Woolf_Dividend_Tracker newDividendTracker = Baby_Woolf_Dividend_Tracker(payable(newAddress));

        require(newDividendTracker.owner() == address(this), "BABYWOOLF: The new dividend tracker must be owned by the BABYWOOLF token contract");

        newDividendTracker.excludeFromDividends(address(newDividendTracker));
        newDividendTracker.excludeFromDividends(address(this));
        newDividendTracker.excludeFromDividends(owner());
        newDividendTracker.excludeFromDividends(address(uniswapV2Router));

        emit UpdateDividendTracker(newAddress, address(dividendTracker));

        dividendTracker = newDividendTracker;
    }

    function updateUniswapV2Router(address newAddress) public onlyOwner {
        require(newAddress != address(uniswapV2Router), "BABYWOOLF: The router already has that address");
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newAddress);
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(_isExcludedFromFees[account] != excluded, "BABYWOOLF: Account is already the value of 'excluded'");
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != uniswapV2Pair, "BABYWOOLF: The PancakeSwap pair cannot be removed from automatedMarketMakerPairs");

        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, "BABYWOOLF: Automated market maker pair is already set to that value");
        automatedMarketMakerPairs[pair] = value;

        if(value) {
            dividendTracker.excludeFromDividends(pair);
        }

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function updateGasForProcessing(uint256 newValue) public onlyOwner {
        require(newValue >= 200000 && newValue <= 500000, "BABYWOOLF: gasForProcessing must be between 200,000 and 500,000");
        require(newValue != gasForProcessing, "BABYWOOLF: Cannot update gasForProcessing to same value");
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    function getClaimWait() external view returns(uint256) {
        return dividendTracker.claimWait();
    }

    function getTotalDividendsDistributed() external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }

    function isExcludedFromFees(address account) public view returns(bool) {
        return _isExcludedFromFees[account];
    }

    function withdrawableDividendOf(address account) public view returns(uint256) {
    	return dividendTracker.withdrawableDividendOf(account);
  	}

	function dividendTokenBalanceOf(address account) public view returns (uint256) {
		return dividendTracker.balanceOf(account);
	}

    function getAccountDividendsInfo(address account)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return dividendTracker.getAccount(account);
    }

	function getAccountDividendsInfoAtIndex(uint256 index)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	return dividendTracker.getAccountAtIndex(index);
    }

	function processDividendTracker(uint256 gas) external {
		(uint256 iterations, uint256 claims, uint256 lastProcessedIndex) = dividendTracker.process(gas);
		emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, false, gas, tx.origin);
    }

    function claim() external {
		dividendTracker.processAccount(payable(msg.sender), false);
    }

    function getLastProcessedIndex() external view returns(uint256) {
    	return dividendTracker.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders() external view returns(uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }
    
    function setBPAddrss(address _bp) external onlyOwner {
        require(address(BP)== address(0), "Can only be initialized once");
        BP = BPContract(_bp);
    }

    function setBpEnabled(bool _enabled) external onlyOwner {
        bpEnabled = _enabled;
    }
    
    function setBotProtectionDisableForever() external onlyOwner{
        require(BPDisabledForever == false);
        BPDisabledForever = true;
    }

    function setSwapTokensAtAmount(uint256 amount) public onlyOwner {
        swapTokensAtAmount = amount;
    }

    function getMaxSellTransactionAmount(address user) public view returns (uint256 amount) {
        uint256 userTokenBalance = balanceOf(user);
        amount = userTokenBalance.mul(1).div(1e3);
        return amount;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "BEP20: transfer from the zero address");
        require(to != address(0), "BEP20: transfer to the zero address");
        require(!isBlackListed[from], "BEP20: You are blacklisted..");
        require(!isBlackListed[to], "BEP20: The receipent blacklisted..");

        uint256 currentLiquidityFee = liquidityFee;

        if (bpEnabled && !BPDisabledForever) {
            BP.protect(from, to, amount);
        }

        // only whitelisted addresses can make transfers after the fixed-sale has started
        // and before the public presale is over
        if(!tradingIsEnabled) {
            require(canTransferBeforeTradingIsEnabled[from], "TIKI: This account cannot send tokens until trading is enabled");
        }

        if(amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        uint256 userTokenBalance = balanceOf(from);
        uint256 maxSellTransactionAmount = userTokenBalance.mul(1).div(1e3);

        if( 
        	!swapping &&
        	tradingIsEnabled &&
            automatedMarketMakerPairs[to] && // sells only by detecting transfer to automated market maker pair
        	from != address(uniswapV2Router) && //router -> pair is removing liquidity which shouldn't have max
            !_isExcludedFromFees[to] //no max for those excluded from fees
        ) {
            if (amount > maxSellTransactionAmount) {
                liquidityFee = largeTokenSellFee;
            }
        }

		uint256 contractTokenBalance = balanceOf(address(this));
        
        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if(
            tradingIsEnabled && 
            canSwap &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            from != liquidityWallet &&
            to != liquidityWallet
        ) {
            swapping = true;
            
            swapAndLiquify(_liquidityFeeTotal);
            swapAndSendDividends(_BNBRewardsTotal);
            swapTokensForEth(metaverseWallet, _metaverseFeeTotal);
            swapTokensForEth(vaultWallet, _vaultFeeTotal);
            swapTokensForEth(appWallet, _appFeeTotal);

            _liquidityFeeTotal = 0;
            _BNBRewardsTotal = 0;
            _metaverseFeeTotal = 0;
            _vaultFeeTotal = 0;
            _appFeeTotal = 0;

            swapping = false;
        }
        
        bool takeFee = tradingIsEnabled && !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        if(takeFee) {
            uint256 transferAmount = amount;
            //@dev Take BNBRewards fee
            if(BNBRewardsFee != 0) {
                uint256 _BNBRewardsFee = amount.mul(BNBRewardsFee).div(1e3);
                transferAmount = transferAmount.sub(_BNBRewardsFee);
                BNBRewardsTotal = BNBRewardsTotal.add(_BNBRewardsFee);
                _BNBRewardsTotal = _BNBRewardsTotal.add(_BNBRewardsFee);
                super._transfer(from, address(this), _BNBRewardsFee);
            }
            //@dev Take Metaverse fee
            if(metaverseFee != 0) {
                uint256 _metaverseFee = amount.mul(metaverseFee).div(1e3);
                transferAmount = transferAmount.sub(_metaverseFee);
                metaverseFeeTotal = metaverseFeeTotal.add(_metaverseFee);
                _metaverseFeeTotal = _metaverseFeeTotal.add(_metaverseFee);
                super._transfer(from, address(this), _metaverseFee);
            }
            //@dev Take Liquidity fee
            if(liquidityFee != 0) {
                uint256 _liquidityFee = amount.mul(liquidityFee).div(1e3);
                transferAmount = transferAmount.sub(_liquidityFee);
                liquidityFeeTotal = liquidityFeeTotal.add(_liquidityFee);
                _liquidityFeeTotal = _liquidityFeeTotal.add(_liquidityFee);
                super._transfer(from, address(this), _liquidityFee);
            }
            //@dev Take Vault fee
            if(vaultFee != 0) {
                uint256 _vaultFee = amount.mul(vaultFee).div(1e3);
                transferAmount = transferAmount.sub(_vaultFee);
                vaultFeeTotal = vaultFeeTotal.add(_vaultFee);
                _vaultFeeTotal = _vaultFeeTotal.add(_vaultFee);
                super._transfer(from, address(this), _vaultFee);
            }
            //@dev Take App fee
            if(appFee != 0) {
                uint256 _appFee = amount.mul(appFee).div(1e3);
                transferAmount = transferAmount.sub(_appFee);
                appFeeTotal = appFeeTotal.add(_appFee);
                _appFeeTotal = _appFeeTotal.add(_appFee);
                super._transfer(from, address(this), _appFee);
            }
            //@dev Take Burn fee
            if(burnFee != 0) {
                uint256 _burnFee = amount.mul(burnFee).div(1e3);
                transferAmount = transferAmount.sub(_burnFee);
                burnFeeTotal = burnFeeTotal.add(_burnFee);
                super._burn(from, _burnFee);
            }
            amount = transferAmount;
        }

        liquidityFee = currentLiquidityFee;

        super._transfer(from, to, amount);

        try dividendTracker.setBalance(payable(from), balanceOf(from)) {} catch {}
        try dividendTracker.setBalance(payable(to), balanceOf(to)) {} catch {}

        if(!swapping) {
	    	uint256 gas = gasForProcessing;

	    	try dividendTracker.process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
	    		emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
	    	} 
	    	catch {

	    	}
        }
    }

    function swapAndLiquify(uint256 tokens) private {
        // split the contract balance into halves
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(address(this), half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);
        
        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForEth(address recipient, uint256 tokenAmount) private {
        
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            recipient,
            block.timestamp
        );
        
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            liquidityWallet,
            block.timestamp
        );
        
    }

    function swapAndSendDividends(uint256 tokens) private {
        swapTokensForEth(address(this), tokens);
        uint256 dividends = address(this).balance;
        (bool success,) = address(dividendTracker).call{value: dividends}("");

        if(success) {
   	 		emit SendDividends(tokens, dividends);
        }
    }
}

contract Baby_Woolf_Dividend_Tracker is DividendPayingToken, Ownable {
    using SafeMath for uint256;
    using SafeMathInt for int256;
    using IterableMapping for IterableMapping.Map;

    IterableMapping.Map private tokenHoldersMap;
    uint256 public lastProcessedIndex;

    mapping (address => bool) public excludedFromDividends;

    mapping (address => uint256) public lastClaimTimes;

    uint256 public claimWait;
    uint256 public immutable minimumTokenBalanceForDividends;

    event ExcludeFromDividends(address indexed account);
    event ClaimWaitUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event Claim(address indexed account, uint256 amount, bool indexed automatic);

    constructor() DividendPayingToken("Baby_Woolf_Dividend_Tracker", "BWDT") {
    	claimWait = 3600;
        minimumTokenBalanceForDividends = 1e24; //must hold 1000000+ tokens
    }

    function _transfer(address, address, uint256) internal pure override {
        require(false, "BABYWOOLF_Dividend_Tracker: No transfers allowed");
    }

    function withdrawDividend() public pure override {
        require(false, "BABYWOOLF_Dividend_Tracker: withdrawDividend disabled. Use the 'claim' function on the main BABYWOOLF contract.");
    }

    function excludeFromDividends(address account) external onlyOwner {
    	require(!excludedFromDividends[account]);
    	excludedFromDividends[account] = true;

    	_setBalance(account, 0);
    	tokenHoldersMap.remove(account);

    	emit ExcludeFromDividends(account);
    }

    function updateClaimWait(uint256 newClaimWait) external onlyOwner {
        require(newClaimWait >= 3600 && newClaimWait <= 86400, "BABYWOOLF_Dividend_Tracker: claimWait must be updated to between 1 and 24 hours");
        require(newClaimWait != claimWait, "BABYWOOLF_Dividend_Tracker: Cannot update claimWait to same value");
        emit ClaimWaitUpdated(newClaimWait, claimWait);
        claimWait = newClaimWait;
    }

    function getLastProcessedIndex() external view returns(uint256) {
    	return lastProcessedIndex;
    }

    function getNumberOfTokenHolders() external view returns(uint256) {
        return tokenHoldersMap.keys.length;
    }



    function getAccount(address _account)
        public view returns (
            address account,
            int256 index,
            int256 iterationsUntilProcessed,
            uint256 withdrawableDividends,
            uint256 totalDividends,
            uint256 lastClaimTime,
            uint256 nextClaimTime,
            uint256 secondsUntilAutoClaimAvailable) {
        account = _account;

        index = tokenHoldersMap.getIndexOfKey(account);

        iterationsUntilProcessed = -1;

        if(index >= 0) {
            if(uint256(index) > lastProcessedIndex) {
                iterationsUntilProcessed = index.sub(int256(lastProcessedIndex));
            }
            else {
                uint256 processesUntilEndOfArray = tokenHoldersMap.keys.length > lastProcessedIndex ?
                                                        tokenHoldersMap.keys.length.sub(lastProcessedIndex) :
                                                        0;


                iterationsUntilProcessed = index.add(int256(processesUntilEndOfArray));
            }
        }


        withdrawableDividends = withdrawableDividendOf(account);
        totalDividends = accumulativeDividendOf(account);

        lastClaimTime = lastClaimTimes[account];

        nextClaimTime = lastClaimTime > 0 ?
                                    lastClaimTime.add(claimWait) :
                                    0;

        secondsUntilAutoClaimAvailable = nextClaimTime > block.timestamp ?
                                                    nextClaimTime.sub(block.timestamp) :
                                                    0;
    }

    function getAccountAtIndex(uint256 index)
        public view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	if(index >= tokenHoldersMap.size()) {
            return (0x0000000000000000000000000000000000000000, -1, -1, 0, 0, 0, 0, 0);
        }

        address account = tokenHoldersMap.getKeyAtIndex(index);

        return getAccount(account);
    }

    function canAutoClaim(uint256 lastClaimTime) private view returns (bool) {
    	if(lastClaimTime > block.timestamp)  {
    		return false;
    	}

    	return block.timestamp.sub(lastClaimTime) >= claimWait;
    }

    function setBalance(address payable account, uint256 newBalance) external onlyOwner {
    	if(excludedFromDividends[account]) {
    		return;
    	}

    	if(newBalance >= minimumTokenBalanceForDividends) {
            _setBalance(account, newBalance);
    		tokenHoldersMap.set(account, newBalance);
    	}
    	else {
            _setBalance(account, 0);
    		tokenHoldersMap.remove(account);
    	}

    	processAccount(account, true);
    }

    function process(uint256 gas) public returns (uint256, uint256, uint256) {
    	uint256 numberOfTokenHolders = tokenHoldersMap.keys.length;

    	if(numberOfTokenHolders == 0) {
    		return (0, 0, lastProcessedIndex);
    	}

    	uint256 _lastProcessedIndex = lastProcessedIndex;

    	uint256 gasUsed = 0;

    	uint256 gasLeft = gasleft();

    	uint256 iterations = 0;
    	uint256 claims = 0;

    	while(gasUsed < gas && iterations < numberOfTokenHolders) {
    		_lastProcessedIndex++;

    		if(_lastProcessedIndex >= tokenHoldersMap.keys.length) {
    			_lastProcessedIndex = 0;
    		}

    		address account = tokenHoldersMap.keys[_lastProcessedIndex];

    		if(canAutoClaim(lastClaimTimes[account])) {
    			if(processAccount(payable(account), true)) {
    				claims++;
    			}
    		}

    		iterations++;

    		uint256 newGasLeft = gasleft();

    		if(gasLeft > newGasLeft) {
    			gasUsed = gasUsed.add(gasLeft.sub(newGasLeft));
    		}

    		gasLeft = newGasLeft;
    	}

    	lastProcessedIndex = _lastProcessedIndex;

    	return (iterations, claims, lastProcessedIndex);
    }

    function processAccount(address payable account, bool automatic) public onlyOwner returns (bool) {
        uint256 amount = _withdrawDividendOfUser(account);

    	if(amount > 0) {
    		lastClaimTimes[account] = block.timestamp;
            emit Claim(account, amount, automatic);
    		return true;
    	}

    	return false;
    }
}
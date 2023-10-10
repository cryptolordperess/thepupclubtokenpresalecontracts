// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract TokenSale is Ownable {
    using SafeMath for uint256;

    IERC20 public tpcToken;
    address public usdtAddress;
    address public ethAddress;
    address public bnbAddress;
    address public feesReceiver;

    uint256 public tpcRate;
    uint256 public minDeposit;
    uint256 public ethPrice;
    uint256 public bnbPrice;
    uint256 public usdtPrice;
    uint256 public feesPercentage;

    mapping(address => uint256) public userTPCBalances;

    enum PriceSource { USDT, ETH, BNB }
    PriceSource public priceSource;

    event TPCPurchased(address indexed buyer, uint256 inputAmount, uint256 tpcAmount, uint256 fees);
    event TPCWithdrawn(address indexed withdrawer, uint256 amount);

    constructor(
        address _usdtAddress,
        address _ethAddress,
        address _bnbAddress,
        address _feesReceiver,
        uint256 _tpcRate,
        uint256 _minDeposit
    ) {
        tpcToken = IERC20(address(0)); // Replace with the actual TPC token address
        usdtAddress = _usdtAddress;
        ethAddress = _ethAddress;
        bnbAddress = _bnbAddress;
        feesReceiver = _feesReceiver;
        tpcRate = _tpcRate;
        minDeposit = _minDeposit;
        ethPrice = 0.00062 ether; // Default ETH price for 1 TPC
        bnbPrice = 0.005 ether;   // Default BNB price for 1 TPC
        usdtPrice = 500000000000000000; // Default USDT price for 1 TPC (0.5 USDT in ufixed8x18)
       
        priceSource = PriceSource.USDT; // Default price source
        feesPercentage = 1;       // Default fees percentage (1%)
    }

    function setFeesReceiver(address _feesReceiver) external onlyOwner {
        feesReceiver = _feesReceiver;
    }

    function setTPCRate(uint256 _tpcRate) external onlyOwner {
        tpcRate = _tpcRate;
    }

    function setMinDeposit(uint256 _minDeposit) external onlyOwner {
        minDeposit = _minDeposit;
    }

    function setTokenAddresses(
        address _usdtAddress,
        address _ethAddress,
        address _bnbAddress
    ) external onlyOwner {
        usdtAddress = _usdtAddress;
        ethAddress = _ethAddress;
        bnbAddress = _bnbAddress;
    }

    function setPriceSource(PriceSource _priceSource) external onlyOwner {
        priceSource = _priceSource;
    }

    function setEthPrice(uint256 _ethPrice) external onlyOwner {
        ethPrice = _ethPrice;
    }

    function setBnbPrice(uint256 _bnbPrice) external onlyOwner {
        bnbPrice = _bnbPrice;
    }

    function setUsdtPrice(uint256 _usdtPrice) external onlyOwner {
        usdtPrice = _usdtPrice;
    }

    function setFeesPercentage(uint256 _feesPercentage) external onlyOwner {
        require(_feesPercentage <= 100, "Fees percentage cannot exceed 100%");
        feesPercentage = _feesPercentage;
    }

    function getEthBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function setApproval(uint256 amount) external {
        tpcToken.approve(address(this), amount);
    }

    function approveTokenPurchase(uint256 tpcAmount) external {
        require(tpcAmount > 0, "Invalid TPC amount");
        require(tpcToken.allowance(msg.sender, address(this)) >= tpcAmount, "TPC allowance not set");
        _purchaseTPC(msg.sender, tpcAmount);
        tpcToken.transferFrom(msg.sender, address(this), tpcAmount);
    }

    function withdrawAll() external onlyOwner {
        uint256 ethBalance = address(this).balance;
        uint256 usdtBalance = _getUSDTBalance();
        uint256 bnbBalance = _getBNBBalance();

        _transferFees(ethBalance, usdtBalance, bnbBalance);
    }

    function withdrawTPC(uint256 amount) external onlyOwner {
        require(amount > 0, "Invalid withdrawal amount");
        require(tpcToken.balanceOf(address(this)) >= amount, "Not enough TPC tokens in contract");
        tpcToken.transfer(feesReceiver, amount);
        emit TPCWithdrawn(feesReceiver, amount);
    }

    function depositAndBuyTokens(uint256 ethAmount, uint256 tpcAmount) external payable {
        require(msg.value == ethAmount, "Incorrect ETH amount sent");
        require(ethAmount >= minDeposit, "Below minimum deposit");
        _purchaseTPC(msg.sender, tpcAmount);
    }

    function buyWithEth(uint256 ethAmount) external payable {
        require(msg.value == ethAmount, "Incorrect ETH amount sent");
        require(ethAmount >= minDeposit, "Below minimum deposit");
        uint256 tpcAmount = _calculateTPCAmount(ethAmount, PriceSource.ETH);
        _purchaseTPC(msg.sender, tpcAmount);
    }

    function buyWithBnb(uint256 bnbAmount) external payable {
        require(msg.value == bnbAmount, "Incorrect BNB amount sent");
        require(bnbAmount >= minDeposit, "Below minimum deposit");
        uint256 tpcAmount = _calculateTPCAmount(bnbAmount, PriceSource.BNB);
        _purchaseTPC(msg.sender, tpcAmount);
    }

    function buyWithUsdt(uint256 usdtAmount) external {
        require(usdtAmount >= minDeposit, "Below minimum deposit");
        uint256 tpcAmount = _calculateTPCAmount(usdtAmount, PriceSource.USDT);
        _purchaseTPC(msg.sender, tpcAmount);
        IERC20(usdtAddress).transferFrom(msg.sender, feesReceiver, _calculateFees(usdtAmount));
    }

    function _purchaseTPC(address buyer, uint256 tpcAmount) internal {
        uint256 fees = _calculateFees(tpcAmount);
        payable(feesReceiver).transfer(fees);
        tpcToken.transfer(buyer, tpcAmount);
        _updateUserBalance(buyer, tpcAmount);
        emit TPCPurchased(buyer, _calculateEthAmount(tpcAmount), tpcAmount, fees);
    }

    function _transferFees(uint256 ethAmount, uint256 usdtAmount, uint256 bnbAmount) internal {
        if (ethAmount > 0) {
            payable(owner()).transfer(ethAmount);
        }

        if (usdtAmount > 0) {
            IERC20(usdtAddress).transfer(owner(), usdtAmount);
        }

        if (bnbAmount > 0) {
            payable(owner()).transfer(bnbAmount);
        }
    }

    function _calculateFees(uint256 inputAmount) internal view returns (uint256) {
        // Using the feesPercentage state variable
        return (inputAmount * feesPercentage) / 100;
    }

    function _calculateTPCAmount(uint256 inputAmount, PriceSource source) internal view returns (uint256) {
        if (source == PriceSource.USDT) {
            return (inputAmount * usdtPrice) / tpcRate;
        } else if (source == PriceSource.ETH) {
            return (inputAmount * ethPrice) / tpcRate;
        } else if (source == PriceSource.BNB) {
            return (inputAmount * bnbPrice) / tpcRate;
        } else {
            revert("Invalid Price Source");
        }
    }

    function _calculateEthAmount(uint256 tpcAmount) internal view returns (uint256) {
        return (tpcAmount * tpcRate) / ethPrice;
    }

    function _updateUserBalance(address user, uint256 tpcAmount) internal {
        userTPCBalances[user] += tpcAmount;
    }

    function _getUSDTBalance() internal view returns (uint256) {
        if (usdtAddress == address(0)) {
            return 0;
        }
        return IERC20(usdtAddress).balanceOf(address(this));
    }

    function _getBNBBalance() internal view returns (uint256) {
        return address(this).balance;
    }
}

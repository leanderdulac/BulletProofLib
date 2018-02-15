pragma solidity ^0.4.19;

import 'zeppelin-solidity/contracts/token/ERC20/ERC20.sol';
import "./RangeProofVerifier.sol";
import "./alt_bn128.sol";

contract CoinMixer {
    using alt_bn128 for alt_bn128.G1Point;

    mapping (address => alt_bn128.G1Point) public deposits;

    RangeProofVerifier public verifier;

    ERC20 public token;

    alt_bn128.G1Point public peddersenBaseG;
    alt_bn128.G1Point public peddersenBaseH;

    function CoinMixer(
        uint256[4] coords, // [peddersenBaseG_x, peddersenBaseG_y, peddersenBaseH_x, peddersenBaseH_y]
        RangeProofVerifier _verifier,
        ERC20 _token) {
        verifier = _verifier;
        token = _token;
        peddersenBaseG = alt_bn128.G1Point(coords[0], coords[1]);
        peddersenBaseH = alt_bn128.G1Point(coords[2], coords[3]);
    }

    function deposit(uint256 value) external {
        require(deposits[msg.sender].eq(alt_bn128.G1Point(0, 0))); //TODO: move to lib
        require(token.transferFrom(msg.sender, this, value));
        deposits[msg.sender] = peddersenBaseG.mul(value);
    }

    function withdraw(uint256 value, uint256 secret) external {
        require(peddersenBaseG.mul(value).add(peddersenBaseH.mul(secret)).eq(deposits[msg.sender]));
        assert(token.transfer(msg.sender, value));
    }

    function transfer(
        address address1,
        uint256 hiddenValue1_x,
        uint256 hiddenValue1_y,
        address address2,
        uint256 hiddenValue2_x,
        uint256 hiddenValue2_y
    ) external {
        alt_bn128.G1Point memory hiddenValue1 = alt_bn128.G1Point(hiddenValue1_x, hiddenValue1_y);
        alt_bn128.G1Point memory hiddenValue2 = alt_bn128.G1Point(hiddenValue2_x, hiddenValue2_y);
        require(hiddenValue1.add(hiddenValue2).eq(deposits[msg.sender]));
        deposits[msg.sender] = alt_bn128.G1Point(0, 0);
        deposits[address1] = hiddenValue1;
        deposits[address2] = hiddenValue2;
    }
}

pragma solidity ^0.4.19;
pragma experimental ABIEncoderV2;

import "./EfficientInnerProductVerifier.sol";
import "./alt_bn128.sol";

contract RangeProofVerifier {
    using alt_bn128 for uint256;
    using alt_bn128 for alt_bn128.G1Point;

    uint256 public constant m = 4;
    uint256 public constant n = 2;

    alt_bn128.G1Point[m] public gs;
    alt_bn128.G1Point[m] public hs;
    alt_bn128.G1Point public peddersenBaseG;
    alt_bn128.G1Point public peddersenBaseH;

    uint256[m] internal twos = powers(2);

    EfficientInnerProductVerifier public ipVerifier;

    function RangeProofVerifier(
        uint256[4] coords, // [peddersenBaseG_x, peddersenBaseG_y, peddersenBaseH_x, peddersenBaseH_y]
        uint256[2 * m] gs_coords,
        uint256[2 * m] hs_coords,
        EfficientInnerProductVerifier _ipVerifier
    ) public {
        peddersenBaseG = alt_bn128.G1Point(coords[0], coords[1]);
        peddersenBaseH = alt_bn128.G1Point(coords[2], coords[3]);
        for (uint8 i = 0; i < m; i++) {
            gs[i] = alt_bn128.G1Point(gs_coords[i], gs_coords[m + i]);
            hs[i] = alt_bn128.G1Point(hs_coords[i], hs_coords[m + i]);
        }
        ipVerifier = _ipVerifier;
    }

    function verify(
        uint256[10] coords, // [input_x, input_y, A_x, A_y, S_x, S_y, commits[0]_x, commits[0]_y, commits[1]_x, commits[1]_y]
        uint256[5] scalars, // [tauX, mu, t, a, b]
        uint256[] ls_coords, // 2 * n
        uint256[] rs_coords  // 2 * n
    ) external view returns (bool) {
        RangeProof memory rangeProof;
        alt_bn128.G1Point memory input = alt_bn128.G1Point(coords[0], coords[1]);
        rangeProof.A = alt_bn128.G1Point(coords[2], coords[3]);
        rangeProof.S = alt_bn128.G1Point(coords[4], coords[5]);
        rangeProof.commits = [alt_bn128.G1Point(coords[6], coords[7]), alt_bn128.G1Point(coords[8], coords[9])];
        rangeProof.tauX = scalars[0];
        rangeProof.mu = scalars[1];
        rangeProof.t = scalars[2];
        InnerProductProof memory ipProof;
        rangeProof.ipProof = ipProof;
        for (uint8 i = 0; i < n; i++) {
            ipProof.ls[i] = alt_bn128.G1Point(ls_coords[i], ls_coords[n + i]);
            ipProof.rs[i] = alt_bn128.G1Point(rs_coords[i], rs_coords[n + i]);
        }
        ipProof.a = scalars[3];
        ipProof.b = scalars[4];
        return verifyInternal(input, rangeProof);
    }

    struct RangeProof {
        alt_bn128.G1Point A;
        alt_bn128.G1Point S;
        alt_bn128.G1Point[2] commits;
        uint256 tauX;
        uint256 mu;
        uint256 t;
        InnerProductProof ipProof;
    }

    struct InnerProductProof {
        alt_bn128.G1Point[n] ls;
        alt_bn128.G1Point[n] rs;
        uint256 a;
        uint256 b;
    }

    event Proof(uint256 x, uint256 y);

    struct Board {
        uint256 y;
        uint256[m] ys;
        uint256 z;
        uint256 zSquared;
        uint256 zCubed;
        uint256[m] twoTimesZSquared;
        uint256 x;
        alt_bn128.G1Point lhs;
        uint256 k;
        alt_bn128.G1Point rhs;
        uint256 uChallenge;
        alt_bn128.G1Point u;
        alt_bn128.G1Point P;
    }

    function verifyInternal(
        alt_bn128.G1Point input,
        RangeProof proof
    ) internal view returns (bool) {
        Board memory b;
        b.y = uint256(keccak256(input.X, input.Y, proof.A.X, proof.A.Y, proof.S.X, proof.S.Y)).mod();
        b.ys = powers(b.y);
        b.z = uint256(keccak256(b.y)).mod();
        b.zSquared = b.z.mul(b.z);
        b.zCubed = b.zSquared.mul(b.z);
        b.twoTimesZSquared = times(twos, b.zSquared);
        b.x = uint256(keccak256(proof.commits[0].X, proof.commits[0].Y, proof.commits[1].X, proof.commits[1].Y)).mod();
        b.lhs = peddersenBaseG.mul(proof.t).add(peddersenBaseH.mul(proof.tauX));
        b.k = sumScalars(b.ys).mul(b.z.sub(b.zSquared)).sub(b.zCubed.mul(2 ** m).sub(b.zCubed));
        b.rhs = proof.commits[0].mul(b.x).add(proof.commits[1].mul(b.x.mul(b.x)));
        b.rhs = b.rhs.add(input.mul(b.zSquared));
        b.rhs = b.rhs.add(peddersenBaseG.mul(b.k));
        if (!b.rhs.eq(b.lhs)) {
            return false;
        }
        b.uChallenge = uint256(keccak256(proof.tauX, proof.mu, proof.t)).mod();
        b.u = peddersenBaseG.mul(b.uChallenge);
        alt_bn128.G1Point[m] memory hPrimes = haddamard_inv(hs, b.ys);
        uint256[m] memory hExp = addVectors(times(b.ys, b.z), b.twoTimesZSquared);
        b.P = proof.A.add(proof.S.mul(b.x));
        b.P = b.P.add(sumPoints(gs).mul(b.z.neg()));
        b.P = b.P.add(commit(hPrimes, hExp));
        b.P = b.P.add(peddersenBaseH.mul(proof.mu).neg());
        b.P = b.P.add(b.u.mul(proof.t));
        return ipVerifier.verifyWithCustomParams(b.P, toXs(proof.ipProof.ls), toYs(proof.ipProof.ls), toXs(proof.ipProof.rs), toYs(proof.ipProof.rs), proof.ipProof.a, proof.ipProof.b, hPrimes, b.u);
    }

    function addVectors(uint256[m] a, uint256[m] b) internal pure returns (uint256[m] result) {
        for (uint8 i = 0; i < m; i++) {
            result[i] = a[i].add(b[i]);
        }
    }

    function haddamard_inv(alt_bn128.G1Point[m] ps, uint256[m] ss) internal view returns (alt_bn128.G1Point[m] result) {
        for (uint8 i = 0; i < m; i++) {
            result[i] = ps[i].mul(ss[i].inv());
        }
    }

    function sumScalars(uint256[m] ys) internal pure returns (uint256 result) {
        for (uint8 i = 0; i < m; i++) {
            result = result.add(ys[i]);
        }
    }

    function sumPoints(alt_bn128.G1Point[m] ps) internal view returns (alt_bn128.G1Point sum) {
        sum = ps[0];
        for (uint8 i = 1; i < m; i++) {
            sum = sum.add(ps[i]);
        }
    }

    function commit(alt_bn128.G1Point[m] ps, uint256[m] ss) internal view returns (alt_bn128.G1Point commit) {
        commit = ps[0].mul(ss[0]);
        for (uint8 i = 1; i < m; i++) {
            commit = commit.add(ps[i].mul(ss[i]));
        }
    }

    function toXs(alt_bn128.G1Point[n] ps) internal pure returns (uint256[n] xs) {
        for (uint8 i = 0; i < n; i++) {
            xs[i] = ps[i].X;
        }
    }

    function toYs(alt_bn128.G1Point[n] ps) internal pure returns (uint256[n] ys) {
        for (uint8 i = 0; i < n; i++) {
            ys[i] = ps[i].Y;
        }
    }

    function powers(uint256 base) internal pure returns (uint256[m] powers) {
        powers[0] = 1;
        powers[1] = base;
        for (uint8 i = 2; i < m; i++) {
            powers[i] = powers[i-1].mul(base);
        }
    }

    function times(uint256[m] v, uint256 x) internal pure returns (uint256[m] result) {
        for (uint8 i = 0; i < m; i++) {
            result[i] = v[i].mul(x);
        }
    }
}

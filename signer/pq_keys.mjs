// "Starknet PQ key backup v0.1": one BIP39 mnemonic -> STARK-curve ECDSA key + Falcon-512 key.
// "v0.2" (PF-14, PF-13; contracts/docs/key-backup-v0.2.md): the same with a Falcon-1024 or an
// ML-DSA-44 key. ML-DSA-44 key generation is fixed by FIPS 204 (KeyGen_internal of a 32-byte seed).
// Falcon keygen is @noble/post-quantum's deterministic keygen(seed48), so the same mnemonic
// yields the same key in Node and in the browser. TESTNET / DEMO ONLY.
//
// The ECDSA key can follow an existing wallet's derivation, so the words a user already has
// restore both the account's current key and the new Falcon key:
//   "pq"      this profile: BIP32 from the BIP39 seed, m/44'/9004'/0'/0/i, grindKey
//   "argentx" Argent X / Ready: the BIP39 words give an Ethereum key (m/44'/60'/0'/0/0, as
//             ethers HDNodeWallet.fromPhrase); that key is the BIP32 master seed for
//             m/44'/9004'/0'/0/i, then grindKey (argent-x ArgentSigner.ts)
//   "braavos" same computation as "pq"; Braavos does not publish its wallet code, so this
//             matches third-party scripts only and is unconfirmed
// The Falcon key always comes from the BIP39 seed, independent of the ECDSA profile.
import { mnemonicToSeedSync, validateMnemonic } from "@scure/bip39";
import { wordlist } from "@scure/bip39/wordlists/english";
import { HDKey } from "@scure/bip32";
import { getStarkKey, grindKey } from "@scure/starknet";
import { hkdf } from "@noble/hashes/hkdf";
import { sha512 } from "@noble/hashes/sha2";
import { hexToBytes } from "@noble/hashes/utils";
import { falcon512, falcon1024 } from "@noble/post-quantum/falcon.js";
import { ml_dsa44 } from "@noble/post-quantum/ml-dsa.js";

export const PROFILE = "starknet-pq-backup-v0.1";
// PQ scheme -> the backup profile (HKDF salt) that defines its key, the HKDF info tag, the seed
// length and the keygen.
export const PQ_SCHEMES = {
  "falcon-512": { profile: PROFILE, tag: "noble", seedBytes: 48, keygen: falcon512.keygen },
  "falcon-1024": { profile: "starknet-pq-backup-v0.2", tag: "noble", seedBytes: 48, keygen: falcon1024.keygen },
  "ml-dsa-44": { profile: "starknet-pq-backup-v0.2", tag: "fips204", seedBytes: 32, keygen: ml_dsa44.keygen },
};
export const ECDSA_PROFILES = ["pq", "argentx", "braavos"];
const utf8 = (s) => new TextEncoder().encode(s);
const hex0x = (h) => (h.startsWith("0x") ? h : "0x" + h);

function starkKeyFromMaster(masterSeed, index) {
  const node = HDKey.fromMasterSeed(masterSeed).derive(`m/44'/9004'/0'/0/${index}`);
  const ecdsaPrivateKey = hex0x(grindKey(node.privateKey));
  const ecdsaPublicKey = "0x" + BigInt(getStarkKey(ecdsaPrivateKey)).toString(16);
  return { ecdsaPrivateKey, ecdsaPublicKey };
}

/** Argent X: an Ethereum private key (hex) is the master seed, leading zero bytes dropped. */
export function argentStarkKeyFromSecret(secretHex, index = 0) {
  let h = BigInt(secretHex).toString(16);
  if (h.length % 2) h = "0" + h;
  return starkKeyFromMaster(hexToBytes(h), index);
}

export function ethereumPrivateKey(seed) {
  const node = HDKey.fromMasterSeed(seed).derive("m/44'/60'/0'/0/0");
  return "0x" + Buffer.from(node.privateKey).toString("hex");
}

export function deriveAccountKeys(mnemonic, index = 0, ecdsaProfile = "pq", scheme = "falcon-512") {
  if (!validateMnemonic(mnemonic, wordlist)) throw new Error("invalid mnemonic");
  if (!ECDSA_PROFILES.includes(ecdsaProfile)) throw new Error(`unknown ECDSA profile ${ecdsaProfile}`);
  if (!PQ_SCHEMES[scheme]) throw new Error(`unknown PQ scheme ${scheme}`);
  const seed = mnemonicToSeedSync(mnemonic);
  const { ecdsaPrivateKey, ecdsaPublicKey } =
    ecdsaProfile === "argentx"
      ? argentStarkKeyFromSecret(ethereumPrivateKey(seed), index)
      : starkKeyFromMaster(seed, index);
  const { profile, tag, seedBytes, keygen } = PQ_SCHEMES[scheme];
  const falconSeed = hkdf(sha512, seed, utf8(profile), utf8(`${scheme}/${tag}/account/${index}`), seedBytes);
  const { publicKey: falconPublicKey, secretKey: falconSecretKey } = keygen(falconSeed);
  return { ecdsaPrivateKey, ecdsaPublicKey, falconPublicKey, falconSecretKey };
}

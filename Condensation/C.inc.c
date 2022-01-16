#insert "../../c/configuration/default.inc.h"
#insert "../../c/random/dev-urandom.inc.c"
#insert "../../c/Condensation/littleEndian.inc.c"
#insert "../../c/Condensation/all.inc.h"
#insert "../../c/Condensation/all.inc.c"
#include <stdlib.h>
#include <stdint.h>

static struct cdsBytes bytesFromSV(SV * sv) {
	if (! SvPOK(sv)) return cdsEmpty;
	return cdsBytes((const uint8_t *) SvPVX(sv), SvCUR(sv));
}

static SV * svFromBytes(struct cdsBytes bytes) {
	return newSVpvn((const char *) bytes.data, bytes.length);
}

static SV * svFromBigInteger(struct cdsBigInteger * bigInteger) {
	uint8_t buffer[256];
	struct cdsBytes bytes = cdsBytesFromBigInteger(cdsMutableBytes(buffer, 256), bigInteger);
	return newSVpvn((const char *) bytes.data, bytes.length);
}

// *** Random bytes ***

// Generates max. 256 random bytes
SV * randomBytes(SV * svCount) {
	int count = SvIV(svCount);
	if (count > 256) count = 256;
	if (count < 0) count = 0;
	uint8_t buffer[256];
	return svFromBytes(cdsRandomBytes(buffer, count));
}

// *** SHA256 ***

SV * sha256(SV * svBytes) {
	uint8_t buffer[32];
	struct cdsBytes hash = cdsSHA256(bytesFromSV(svBytes), buffer);
	return svFromBytes(hash);
}

// *** AES ***

SV * aesCrypt(SV * svBytes, SV * svKey, SV * svStartCounter) {
	// Prepare the input
	struct cdsBytes bytes = bytesFromSV(svBytes);
	struct cdsBytes key = bytesFromSV(svKey);
	if (key.length != 32) return &PL_sv_undef;
	struct cdsBytes startCounter = bytesFromSV(svStartCounter);
	if (startCounter.length != 16) return &PL_sv_undef;

	// Crypt
	SV * svResult = newSV(bytes.length < 1 ? 1 : bytes.length);	// newSV(0) has different semantics
	struct cdsAES256 aes;
	cdsInitializeAES256(&aes, key);
	cdsCrypt(&aes, bytes, startCounter, (uint8_t *) SvPVX(svResult));

	// Set the "string" bit, and the length
	SvPOK_only(svResult);
	SvCUR_set(svResult, bytes.length);
	return svResult;
}

SV * counterPlusInt(SV * svCounter, SV * svAdd) {
	struct cdsBytes counter = bytesFromSV(svCounter);
	if (counter.length != 16) return &PL_sv_undef;
	int add = SvIV(svAdd);

	uint8_t buffer[16];
	struct cdsMutableBytes result = cdsMutableBytes(buffer, 16);
	for (int i = 15; i >= 0; i--) {
		add += counter.data[i];
		result.data[i] = add & 0xff;
		add = add >> 8;
	}

	return svFromBytes(cdsSeal(result));
}

// *** RSA Private Key ***

static struct cdsRSAPrivateKey * privateKeyFromSV(SV * sv) {
	if (! SvPOK(sv)) return NULL;
	STRLEN length;
	struct cdsRSAPrivateKey * key = (struct cdsRSAPrivateKey *) SvPV(sv, length);
	return length == sizeof(struct cdsRSAPrivateKey) ? key : NULL;
}

SV * privateKeyGenerate() {
	struct cdsRSAPrivateKey key;
	cdsGeneratePrivateKey(&key);
	SV * obj = newSVpvn((char *) &key, sizeof(struct cdsRSAPrivateKey));
	SvREADONLY_on(obj);
	return obj;
}

SV * privateKeyNew(SV * svE, SV * svP, SV * svQ) {
	struct cdsRSAPrivateKey key;
	cdsInitializePrivateKey(&key, bytesFromSV(svE), bytesFromSV(svP), bytesFromSV(svQ));
	if (! key.isValid) return &PL_sv_undef;
	SV * obj = newSVpvn((char *) &key, sizeof(struct cdsRSAPrivateKey));
	SvREADONLY_on(obj);
	return obj;
}

SV * privateKeyE(SV * svThis) {
	struct cdsRSAPrivateKey * this = privateKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;
	return svFromBigInteger(&this->rsaPublicKey.e);
}

SV * privateKeyP(SV * svThis) {
	struct cdsRSAPrivateKey * this = privateKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;
	return svFromBigInteger(&this->p);
}

SV * privateKeyQ(SV * svThis) {
	struct cdsRSAPrivateKey * this = privateKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;
	return svFromBigInteger(&this->q);
}

SV * privateKeyD(SV * svThis) {
	struct cdsRSAPrivateKey * this = privateKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;
	return svFromBigInteger(&this->d);
}

SV * privateKeySign(SV * svThis, SV * svDigest) {
	struct cdsRSAPrivateKey * this = privateKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;

	uint8_t buffer[256];
	struct cdsBytes signature = cdsSign(this, bytesFromSV(svDigest), buffer);
	return svFromBytes(signature);
}

SV * privateKeyVerify(SV * svThis, SV * svDigest, SV * svSignature) {
	struct cdsRSAPrivateKey * this = privateKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;

	bool ok = cdsVerify(&this->rsaPublicKey, bytesFromSV(svDigest), bytesFromSV(svSignature));
	return ok ? &PL_sv_yes : &PL_sv_no;
}

SV * privateKeyEncrypt(SV * svThis, SV * svMessage) {
	struct cdsRSAPrivateKey * this = privateKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;

	uint8_t buffer[256];
	struct cdsBytes encrypted = cdsEncrypt(&this->rsaPublicKey, bytesFromSV(svMessage), buffer);
	return svFromBytes(encrypted);
}

SV * privateKeyDecrypt(SV * svThis, SV * svMessage) {
	struct cdsRSAPrivateKey * this = privateKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;

	uint8_t buffer[256];
	struct cdsBytes decrypted = cdsDecrypt(this, bytesFromSV(svMessage), buffer);
	return svFromBytes(decrypted);
}

// *** RSA Public Key ***

static struct cdsRSAPublicKey * publicKeyFromSV(SV * sv) {
	if (! SvPOK(sv)) return NULL;
	STRLEN length;
	struct cdsRSAPublicKey * key = (struct cdsRSAPublicKey *) SvPV(sv, length);
	return length == sizeof(struct cdsRSAPublicKey) ? key : NULL;
}

SV * publicKeyFromPrivateKey(SV * svPrivateKey) {
	struct cdsRSAPrivateKey * key = privateKeyFromSV(svPrivateKey);

	// Make a copy of the public key
	struct cdsRSAPublicKey publicKey;
	memcpy(&publicKey.e, &key->rsaPublicKey.e, sizeof(struct cdsBigInteger));
	memcpy(&publicKey.n, &key->rsaPublicKey.n, sizeof(struct cdsBigInteger));

	SV * obj = newSVpvn((char *) &publicKey, sizeof(struct cdsRSAPublicKey));
	SvREADONLY_on(obj);
	return obj;
}

SV * publicKeyNew(SV * svE, SV * svN) {
	struct cdsRSAPublicKey key;
	cdsInitializePublicKey(&key, bytesFromSV(svE), bytesFromSV(svN));
	if (! key.isValid) return &PL_sv_undef;
	SV * obj = newSVpvn((char *) &key, sizeof(struct cdsRSAPublicKey));
	SvREADONLY_on(obj);
	return obj;
}

SV * publicKeyE(SV * svThis) {
	struct cdsRSAPublicKey * this = publicKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;
	return svFromBigInteger(&this->e);
}

SV * publicKeyN(SV * svThis) {
	struct cdsRSAPublicKey * this = publicKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;
	return svFromBigInteger(&this->n);
}

SV * publicKeyVerify(SV * svThis, SV * svDigest, SV * svSignature) {
	struct cdsRSAPublicKey * this = publicKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;

	bool ok = cdsVerify(this, bytesFromSV(svDigest), bytesFromSV(svSignature));
	return ok ? &PL_sv_yes : &PL_sv_no;
}

SV * publicKeyEncrypt(SV * svThis, SV * svMessage) {
	struct cdsRSAPublicKey * this = publicKeyFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;

	uint8_t buffer[256];
	struct cdsBytes encrypted = cdsEncrypt(this, bytesFromSV(svMessage), buffer);
	return svFromBytes(encrypted);
}

// *** Performance timer ***

SV * performanceStart() {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
	SV * obj = newSVpvn((char *) &ts, sizeof(struct timespec));
	SvREADONLY_on(obj);
	return obj;
}

static struct timespec * timerFromSV(SV * sv) {
	if (! SvPOK(sv)) return NULL;
	STRLEN length;
	struct timespec * ts = (struct timespec *) SvPV(sv, length);
	return length == sizeof(struct timespec) ? ts : NULL;
}

SV * performanceElapsed(SV * svThis) {
	struct timespec * this = timerFromSV(svThis);
	if (this == NULL) return &PL_sv_undef;

	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
	time_t dsec = ts.tv_sec - this->tv_sec;
	long dnano = ts.tv_nsec - this->tv_nsec;

	long diff = (long) dsec * 1000 * 1000 + dnano / 1000;
	return newSViv(diff);
}

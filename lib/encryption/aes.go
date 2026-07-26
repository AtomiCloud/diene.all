package encryption

import (
	"crypto/aes"
	"crypto/cipher"
	cryptorand "crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

const (
	problemVersion          = "v1"
	problemInvalidKey       = "invalid-encryption-key"
	problemEncryptionFailed = "encryption-failed"
	problemDecryptionFailed = "decryption-failed"
	envelopeVersion         = 1
	keySizeBytes            = 32
)

// Encryptor protects and restores application payloads.
type Encryptor interface {
	Encrypt(plaintext string) (string, error)
	Decrypt(payload string) (string, error)
}

// AES256GCM encrypts payloads using a fresh AES-GCM nonce per operation.
type AES256GCM struct {
	block  cipher.Block
	random io.Reader
}

type envelope struct {
	Ciphertext string `json:"ciphertext"`
	IV         string `json:"iv"`
	Version    int    `json:"version"`
}

// NewAES256GCM constructs an AES-256-GCM encryptor from a base64 key.
// A nil random reader selects crypto/rand.Reader.
func NewAES256GCM(encodedKey string, random io.Reader) (*AES256GCM, error) {
	key, err := base64.StdEncoding.DecodeString(encodedKey)
	if err != nil {
		return nil, encryptionError(invalidKeyType(), "encryption key is not valid base64", err)
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, encryptionError(invalidKeyType(), "encryption key is not a valid AES key", err)
	}
	if len(key) != keySizeBytes {
		cause := fmt.Errorf("decoded encryption key has %d bytes, want %d", len(key), keySizeBytes)
		return nil, encryptionError(invalidKeyType(), "encryption key must decode to exactly 32 bytes", cause)
	}
	if random == nil {
		random = cryptorand.Reader
	}
	return &AES256GCM{block: block, random: random}, nil
}

// Encrypt returns a versioned JSON envelope containing base64 ciphertext and nonce.
func (encryptor *AES256GCM) Encrypt(plaintext string) (string, error) {
	aead, _ := cipher.NewGCM(encryptor.block)
	iv := make([]byte, aead.NonceSize())
	if _, err := io.ReadFull(encryptor.random, iv); err != nil {
		return "", encryptionError(encryptionFailedType(), "failed to generate an encryption nonce", err)
	}
	ciphertext := aead.Seal(nil, iv, []byte(plaintext), nil)
	encoded, _ := json.Marshal(envelope{
		Ciphertext: base64.StdEncoding.EncodeToString(ciphertext),
		IV:         base64.StdEncoding.EncodeToString(iv),
		Version:    envelopeVersion,
	})
	return string(encoded), nil
}

// Decrypt validates and opens a versioned AES-GCM envelope.
func (encryptor *AES256GCM) Decrypt(payload string) (string, error) {
	decoded, err := decodeEnvelope(payload)
	if err != nil {
		return "", encryptionError(decryptionFailedType(), "encrypted payload is malformed", err)
	}
	if decoded.Version != envelopeVersion {
		cause := fmt.Errorf("envelope version %d is unsupported", decoded.Version)
		return "", encryptionError(decryptionFailedType(), "encrypted payload version is unsupported", cause)
	}
	if decoded.IV == "" || decoded.Ciphertext == "" {
		cause := errors.New("encrypted payload fields must not be blank")
		return "", encryptionError(decryptionFailedType(), "encrypted payload fields are incomplete", cause)
	}
	iv, err := base64.StdEncoding.DecodeString(decoded.IV)
	if err != nil {
		return "", encryptionError(decryptionFailedType(), "encrypted payload nonce is not valid base64", err)
	}
	ciphertext, err := base64.StdEncoding.DecodeString(decoded.Ciphertext)
	if err != nil {
		return "", encryptionError(decryptionFailedType(), "encrypted payload ciphertext is not valid base64", err)
	}
	aead, _ := cipher.NewGCM(encryptor.block)
	if len(iv) != aead.NonceSize() {
		cause := fmt.Errorf("encrypted payload nonce has %d bytes, want %d", len(iv), aead.NonceSize())
		return "", encryptionError(decryptionFailedType(), "encrypted payload nonce has the wrong size", cause)
	}
	plaintext, err := aead.Open(nil, iv, ciphertext, nil)
	if err != nil {
		return "", encryptionError(decryptionFailedType(), "failed to authenticate encrypted payload", err)
	}
	return string(plaintext), nil
}

func decodeEnvelope(payload string) (envelope, error) {
	decoder := json.NewDecoder(strings.NewReader(payload))
	decoder.DisallowUnknownFields()
	var decoded envelope
	if err := decoder.Decode(&decoded); err != nil {
		return envelope{}, err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return envelope{}, errors.New("encrypted payload contains trailing JSON")
	}
	return decoded, nil
}

func invalidKeyType() problem.Type {
	return problem.Type{ID: problemInvalidKey, Title: "Invalid encryption key", Version: problemVersion, Status: 400}
}

func encryptionFailedType() problem.Type {
	return problem.Type{ID: problemEncryptionFailed, Title: "Encryption failed", Version: problemVersion, Status: 500, Recoverable: true}
}

func decryptionFailedType() problem.Type {
	return problem.Type{ID: problemDecryptionFailed, Title: "Decryption failed", Version: problemVersion, Status: 400}
}

func encryptionError(problemType problem.Type, detail string, cause error) error {
	registry, _ := problem.NewRegistry(problem.LocalErrorPortal(), problemType)
	options := problem.DefaultTransformOptions()
	options.Registry = registry
	envelope := problem.FromObject(map[string]any{"problemId": problemType.ID}, options)
	envelope.Detail = &detail
	return problem.WrapError(envelope, cause)
}

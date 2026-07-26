package testhelper

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
)

// emptyPayloadSHA256 is the SigV4 hash of an empty request body, which every
// bucket-creation request carries.
const emptyPayloadSHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

// endpointURL renders the http endpoint a published S3 port is reachable at.
func endpointURL(host string, port int) string {
	return "http://" + host + ":" + strconv.Itoa(port)
}

// CreateBucket creates a bucket on an S3-compatible endpoint with a
// SigV4-signed PUT.
//
// It is signed by hand with the standard library on purpose: pulling an AWS SDK
// into a config-preset library to issue one PUT would add a large dependency to
// every consumer's module graph for a single test-time request. It is exported
// because a consumer whose service uses several buckets needs to create the
// extra ones against the endpoint [StartStorage] returned.
func CreateBucket(ctx context.Context, entry standardconfig.StorageEntry) error {
	target := strings.TrimRight(entry.Endpoint, "/") + "/" + entry.Bucket
	request, err := http.NewRequestWithContext(ctx, http.MethodPut, target, nil)
	if err != nil {
		return fmt.Errorf("standardconfig testhelper: bucket endpoint %q is not usable: %w", target, err)
	}
	sign(request, entry, time.Now().UTC())
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return fmt.Errorf("standardconfig testhelper: create bucket %q: %w", entry.Bucket, err)
	}
	defer func() { _ = response.Body.Close() }()
	body, _ := io.ReadAll(response.Body)
	if response.StatusCode >= http.StatusMultipleChoices {
		return fmt.Errorf("standardconfig testhelper: create bucket %q: HTTP %d: %s",
			entry.Bucket, response.StatusCode, strings.TrimSpace(string(body)))
	}
	return nil
}

// sign applies the AWS SigV4 headers for a bucket-creation PUT to request.
func sign(request *http.Request, entry standardconfig.StorageEntry, stamp time.Time) {
	host := request.URL.Host
	amzDate := stamp.Format("20060102T150405Z")
	date := amzDate[:8]
	scope := date + "/" + entry.Region + "/s3/aws4_request"
	canonicalHeaders := "host:" + host + "\n" +
		"x-amz-content-sha256:" + emptyPayloadSHA256 + "\n" +
		"x-amz-date:" + amzDate + "\n"
	const signedHeaders = "host;x-amz-content-sha256;x-amz-date"
	canonicalRequest := strings.Join([]string{
		http.MethodPut, request.URL.EscapedPath(), "", canonicalHeaders, signedHeaders, emptyPayloadSHA256,
	}, "\n")
	stringToSign := strings.Join([]string{
		"AWS4-HMAC-SHA256", amzDate, scope, sha256hex(canonicalRequest),
	}, "\n")
	key := signingKey(entry.SecretAccessKey, date, entry.Region)
	signature := hex.EncodeToString(mac(key, stringToSign))

	request.Host = host
	request.Header.Set("X-Amz-Date", amzDate)
	request.Header.Set("X-Amz-Content-Sha256", emptyPayloadSHA256)
	request.Header.Set("Authorization", "AWS4-HMAC-SHA256 Credential="+entry.AccessKeyID+"/"+scope+
		", SignedHeaders="+signedHeaders+", Signature="+signature)
}

// signingKey derives the SigV4 date/region/service signing key.
func signingKey(secret, date, region string) []byte {
	return mac(mac(mac(mac([]byte("AWS4"+secret), date), region), "s3"), "aws4_request")
}

// mac returns the HMAC-SHA256 of data under key.
func mac(key []byte, data string) []byte {
	digest := hmac.New(sha256.New, key)
	digest.Write([]byte(data))
	return digest.Sum(nil)
}

// sha256hex returns the lowercase hex SHA-256 of data.
func sha256hex(data string) string {
	sum := sha256.Sum256([]byte(data))
	return hex.EncodeToString(sum[:])
}

package storage

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"os"
)

type Secrets struct {
	PostgresPassword string `json:"postgres_password"`
	RedisPassword    string `json:"redis_password,omitempty"`
	SystemKey        string `json:"system_key"`
}

func GenerateSecret(length int) string {
	bytes := make([]byte, length/2)
	rand.Read(bytes)
	return hex.EncodeToString(bytes)
}

func GeneratePassword(length int) string {
	// URL-safe charset: sem @, #, %, /, ?, & que quebram connection strings
	const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."
	bytes := make([]byte, length)
	rand.Read(bytes)
	for i := range bytes {
		bytes[i] = charset[int(bytes[i])%len(charset)]
	}
	return string(bytes)
}

func LoadSecrets() (*Secrets, error) {
	data, err := os.ReadFile(GetSecretsPath())
	if err != nil {
		if os.IsNotExist(err) {
			return &Secrets{}, nil
		}
		return nil, err
	}

	var secrets Secrets
	if err := json.Unmarshal(data, &secrets); err != nil {
		return nil, err
	}
	return &secrets, nil
}

func SaveSecrets(secrets *Secrets) error {
	if err := EnsureDirectories(); err != nil {
		return err
	}

	data, err := json.MarshalIndent(secrets, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(GetSecretsPath(), data, 0600)
}

func EnsureSecrets() (*Secrets, error) {
	secrets, err := LoadSecrets()
	if err != nil {
		return nil, err
	}

	changed := false

	if secrets.PostgresPassword == "" {
		secrets.PostgresPassword = GeneratePassword(24)
		changed = true
	}

	if secrets.SystemKey == "" {
		secrets.SystemKey = GenerateSecret(64)
		changed = true
	}

	if changed {
		if err := SaveSecrets(secrets); err != nil {
			return nil, err
		}
	}

	return secrets, nil
}

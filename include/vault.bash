cloudbreak-conf-vault() {
    env-import VAULT_BIND_PORT "8200"
    env-import VAULT_CONFIG_FILE "vault-config.hcl"
    env-import VAULT_DB_SCHEMA "vault"
    env-import VAULT_DOCKER_IMAGE "vault"
    env-import VAULT_DOCKER_IMAGE_TAG "0.11.3"
    env-import VAULT_UNSEAL_KEYS ""
    env-import VAULT_AUTO_UNSEAL "false"
}

generate_vault_check_diff() {
    cloudbreak-config

    local verbose="$1"

    if [ -f $VAULT_CONFIG_FILE ]; then
        local vault_delme_path=$TEMP_DIR/vault-delme.hcl
        generate_vault_config_force $vault_delme_path
        if diff $vault_delme_path $VAULT_CONFIG_FILE &> /dev/null; then
            debug "$VAULT_CONFIG_FILE exists and generate wouldn't change it"
            return 0
        else
            if ! [[ "$regeneteInProgress" ]]; then
                warn "$VAULT_CONFIG_FILE already exists, BUT generate would create a DIFFERENT one!"
                warn "please regenerate it:"
                echo "  cbd regenerate" | blue
            fi

            if [[ "$verbose" ]]; then
                warn "expected change:"
                diff $vault_delme_path $VAULT_CONFIG_FILE || true
            else
                debug "expected change:"
                (diff $vault_delme_path $VAULT_CONFIG_FILE || true) | debug-cat
            fi
            return 1
        fi
    else
        generate_vault_config_force $VAULT_CONFIG_FILE
    fi
    return 0

}

generate_vault_config() {
    cloudbreak-config

    if ! generate_vault_check_diff; then
        if [[ ! "$CBD_FORCE_START" ]]; then
            warn "Please check the expected config changes with:"
            echo "  cbd doctor" | blue
            debug "If you want to ignore the changes, set the CBD_FORCE_START to true in Profile"
            _exit 1
        fi
    else
        info "generating $VAULT_CONFIG_FILE"
        generate_vault_config_force $VAULT_CONFIG_FILE
    fi
}

generate_vault_config_force() {
    cloudbreak-config

    declare vaultFile=${1:? required: vault config file path}

    debug "Generating Vault config: ${vaultFile} ..."
    cat > ${vaultFile} << EOF
storage "postgresql" {
  connection_url = "postgres://$CB_DB_ENV_USER:$CB_DB_ENV_PASS@$COMMON_DB.service.consul:5432/$VAULT_DB_SCHEMA?sslmode=disable"
}

listener "tcp" {
 address     = "0.0.0.0:8200"
 tls_disable = 1
}

disable_mlock = true
ui = true
EOF
}

init_vault() {
    cloudbreak-config

    local vault_endpoint="http://vault.service.consul:$VAULT_BIND_PORT"

    local maxtry=${RETRY:=30}
    while ! curl -m 1 $PUBLIC_IP:$VAULT_BIND_PORT/v1/sys/health &>/dev/null; do
        debug "Waiting for Vault to start [tries left: $maxtry]."
        maxtry=$((maxtry-1))
        if [[ $maxtry -gt 0 ]]; then
            sleep 1;
        else
            error "Vault did not start within 30 seconds."
            _exit 1
        fi
    done
    debug "Vault has started"

    set +e
    vaultStatus=$(docker run \
        --dns $PRIVATE_IP \
        --rm \
        -e VAULT_ADDR=$vault_endpoint \
        --entrypoint /bin/sh \
        $VAULT_DOCKER_IMAGE:$VAULT_DOCKER_IMAGE_TAG -c 'vault status -format=json')
    set -e

    debug "Vault status: $vaultStatus"
    initialized=$(echo $vaultStatus | jq .initialized)
    if [[ "$initialized" == "false" ]]; then
        debug "Vault is not initialized yet, initialize now.."
        initLog=$(docker run \
            --dns $PRIVATE_IP \
            --rm \
            -e VAULT_ADDR=$vault_endpoint \
            --entrypoint /bin/sh \
            $VAULT_DOCKER_IMAGE:$VAULT_DOCKER_IMAGE_TAG -c 'vault operator init -key-shares=1 -key-threshold=1 -format=json')


        rootToken=$(echo $initLog | jq '.root_token' -r)
        unsealKeys=$(echo $initLog | jq '.unseal_keys_b64[0]' -r)

        if [[ "$VAULT_AUTO_UNSEAL" == "true" ]]; then
            echo "export VAULT_ROOT_TOKEN=$rootToken" >> $CBD_PROFILE
            echo "export VAULT_UNSEAL_KEYS=$unsealKeys" >> $CBD_PROFILE
            info "$CBD_PROFILE has been updated with the Vault keys"

            vault-unseal $unsealKeys
        else
            warn "Vault auto unseal is disabled so please save the keys in order to use Vault."
            warn "Each time you restart CBD you must unseal Vault with the unseal key."
            warn "You can enable Vault auto unseal by putting the following in your $CBD_PROFILE file"
            warn "export VAULT_AUTO_UNSEAL=true"
            warn "export VAULT_ROOT_TOKEN=$rootToken"
            warn "export VAULT_UNSEAL_KEYS=$unsealKeys"
        fi
    else
        debug "Vault is already initialized"
        if [[ "$VAULT_AUTO_UNSEAL" == "true" ]]; then
            if [[ -z $VAULT_UNSEAL_KEYS ]]; then
                warn "Vault is initialized, but the unseal keys are not provided in the Profile. Please include them in the VAULT_UNSEAL_KEYS var or manually unseal Vault."
                _exit 1
            fi

            vault-unseal $VAULT_UNSEAL_KEYS
        else
            warn "Vault auto unseal is disabled so please unseal Vault now in order to use it."
        fi

    fi

}

vault-unseal() {
    declare desc="Unseal Vault from $CBD_PROFILE file or argument"

    cloudbreak-config

    declare vault_unseal_keys=${1:-$VAULT_UNSEAL_KEYS}
    if [[ -z "$vault_unseal_keys" ]]; then
        warn "Vault unseal key is not in your $CBD_PROFILE file"
        warn "Please provide it with: export VAULT_UNSEAL_KEYS=mykey"
        warn "or provide it as an argument for this command"
        _exit 1
    fi

    local vault_endpoint="http://vault.service.consul:$VAULT_BIND_PORT"

    docker run \
        --dns $PRIVATE_IP \
        --rm \
        -e VAULT_ADDR=$vault_endpoint \
        -e VAULT_UNSEAL_KEYS=$vault_unseal_keys \
        --entrypoint /bin/sh \
        $VAULT_DOCKER_IMAGE:$VAULT_DOCKER_IMAGE_TAG -c 'vault operator unseal $VAULT_UNSEAL_KEYS &>/dev/null'
    info "Vault is unsealed"
}

vault-status() {
    declare desc="Shows the status of Vault in json format"

    cloudbreak-config

    local vault_endpoint="http://vault.service.consul:$VAULT_BIND_PORT"

    docker run \
        --dns $PRIVATE_IP \
        --rm \
        -e VAULT_ADDR=$vault_endpoint \
        --entrypoint /bin/sh \
        $VAULT_DOCKER_IMAGE:$VAULT_DOCKER_IMAGE_TAG -c 'vault status -format=json'
}
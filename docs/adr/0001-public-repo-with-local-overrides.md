# Public repo, with work and identity details in Local overrides

The repo is public so it can be shared and cloned onto any Machine without credentials. Anything tied to one Machine or to work (git identities and emails, client names, internal hostnames) lives in Local overrides that are never committed, and Secrets live only in the Vault. We accepted having to recreate Local overrides by hand on each new Machine instead of a private repo that could hold them, because anything pushed to a public repo stays in its history for good.

forge coverage --no-match-coverage "(script|test|Foo|Bar|validator|sdk|signer)" --report lcov && genhtml lcov.info --output-directory coverage --ignore-errors inconsistent --ignore-errors corrupt


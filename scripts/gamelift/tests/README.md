# GameLift Scripts Test Suite

This directory contains comprehensive test suites for all GameLift scripts to ensure they work correctly and handle edge cases properly.

## Test Scripts

### Individual Test Scripts

1. **`test_generate_auth_token.sh`** - Tests the `generate_auth_token.sh` script
   - Parameter validation
   - Output format validation
   - Environment variable support
   - Cleanup functionality
   - Edge cases and error handling

2. **`test_register_compute.sh`** - Tests the `register_compute.sh` script
   - Parameter validation
   - Fleet ID validation
   - Compute name generation
   - IP address validation
   - Output format validation
   - Cleanup functionality
   - Edge cases and error handling

3. **`test_setup_game_server.sh`** - Tests the `setup_game_server.sh` script
   - Parameter validation
   - Instance ID validation
   - Fleet ID validation
   - Environment format validation
   - Debug functionality
   - Cleanup functionality
   - Edge cases and error handling

### Master Test Runner

**`run_all_tests.sh`** - Runs all test scripts and provides a summary of results.

## Usage

### Prerequisites

Before running the tests, ensure you have:

1. **AWS CLI** installed and configured with valid credentials
2. **jq** installed for JSON processing
3. **Bash** shell (version 4.0 or later)
4. **Internet connectivity** for AWS API calls

### Running All Tests

```bash
# Run all test scripts
./run_all_tests.sh

# Run with verbose output
./run_all_tests.sh --verbose

# List available test scripts
./run_all_tests.sh --list
```

### Running Individual Tests

```bash
# Run specific test script
./run_all_tests.sh generate_auth_token
./run_all_tests.sh register_compute
./run_all_tests.sh setup_game_server

# Or run directly
./test_generate_auth_token.sh
./test_register_compute.sh
./test_setup_game_server.sh
```

### Test Options

Each individual test script supports the following options:

```bash
# Show help
./test_script_name.sh --help

# Clean up test files
./test_script_name.sh --cleanup

# Run with verbose output
./test_script_name.sh --verbose
```

## Test Categories

### 1. Basic Functionality Tests
- Help option display
- Script syntax validation
- Basic parameter parsing

### 2. Parameter Validation Tests
- Required parameter validation
- Optional parameter handling
- Invalid parameter rejection
- Edge cases (empty values, very long values)

### 3. Output Format Tests
- Valid output format handling
- Invalid output format rejection
- Multiple format combinations

### 4. Environment Variable Tests
- Environment variable support
- Default value handling
- Variable precedence

### 5. Cleanup Functionality Tests
- Temporary file cleanup
- Environment variable cleanup
- Output file cleanup

### 6. AWS Integration Tests
- AWS CLI availability
- AWS credentials validation
- AWS API calls (when possible)

### 7. Error Handling Tests
- Graceful error handling
- Appropriate exit codes
- Error message validation

## Test Results

Each test script provides detailed output including:

- **Test Name**: Description of what is being tested
- **Test Status**: PASS/FAIL with exit code information
- **Summary**: Total tests run, passed, and failed
- **Detailed Output**: Available in test output files

### Output Files

Test results are stored in the `test_output/` directory:
- `{test_name}.out` - Standard output from tests
- `{test_name}.err` - Error output from tests

## Expected Behavior

### Without AWS Credentials
- Basic syntax and parameter validation tests should pass
- AWS-dependent tests will fail gracefully with appropriate error messages
- Test suite will continue running other tests

### With AWS Credentials
- All tests should run
- Some tests may fail due to invalid test data (expected behavior)
- AWS API validation tests will provide more accurate results

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   chmod +x test_script_name.sh
   ```

2. **AWS Credentials Not Configured**
   ```bash
   aws configure
   ```

3. **jq Not Installed**
   ```bash
   # macOS
   brew install jq
   
   # Ubuntu/Debian
   sudo apt-get install jq
   
   # CentOS/RHEL
   sudo yum install jq
   ```

4. **Test Files Not Found**
   - Ensure you're running from the correct directory
   - Check that all test scripts exist and are executable

### Debug Mode

For detailed debugging information, run tests with verbose output:

```bash
./run_all_tests.sh --verbose
```

## Adding New Tests

To add new tests to an existing test script:

1. Create a new test function following the naming convention `test_function_name()`
2. Use the `run_test()` function to execute the test
3. Add the test function call to the `run_all_tests()` function
4. Update this README if needed

### Test Function Template

```bash
test_new_functionality() {
    run_test "test_name" "command_to_test" expected_exit_code
}
```

## Continuous Integration

These test scripts can be integrated into CI/CD pipelines:

```bash
# In CI pipeline
cd scripts/gamelift/tests
./run_all_tests.sh
if [ $? -eq 0 ]; then
    echo "All tests passed"
else
    echo "Some tests failed"
    exit 1
fi
```

## Contributing

When contributing to the GameLift scripts:

1. **Add Tests**: Create or update test cases for new functionality
2. **Update Documentation**: Keep this README updated
3. **Test Coverage**: Ensure all new features are covered by tests
4. **Edge Cases**: Test edge cases and error conditions

## License

This test suite follows the same license as the main GameLift scripts project.

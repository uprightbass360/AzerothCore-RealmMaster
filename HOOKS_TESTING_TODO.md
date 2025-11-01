# Hooks Testing Todo List

This file tracks the testing progress for the new manifest-driven post-install hooks system.

## Testing Tasks

### ✅ Completed
- [x] **Create git branch for hooks refactoring work** - Branch `feature/hooks-testing` created and pushed

### ⏳ Pending
- [ ] **Run fresh deployment with test Lua modules** - Deploy with MODULE_ELUNA_SCRIPTS=1 and MODULE_EVENT_SCRIPTS=1
- [ ] **Verify hook execution and Lua script copying** - Check that hooks run successfully during module installation
- [ ] **Test modules container logs for errors** - Monitor `docker compose logs ac-modules -f` for hook execution
- [ ] **Validate copy-standard-lua hook functionality** - Ensure Lua scripts are copied to `/azerothcore/lua_scripts`
- [ ] **Test all hook types** - Validate all 4 hook scripts work correctly:
  - copy-standard-lua (for Eluna modules)
  - copy-aio-lua (for AIO modules)
  - mod-ale-patches (for mod-ale compatibility)
  - black-market-setup (for Black Market module)
- [ ] **Enable additional Lua modules for comprehensive testing** - Test with more modules once basic functionality is confirmed

## Current Test Setup
- **Enabled modules**: MODULE_ELUNA=1, MODULE_ELUNA_SCRIPTS=1, MODULE_EVENT_SCRIPTS=1
- **Branch**: feature/hooks-testing
- **Files modified**: 9 files with new hook system implementation

## Expected Results
- Hooks should execute without "unknown hook" warnings
- Lua scripts should be copied to `/azerothcore/lua_scripts/` directory
- Module installation should complete successfully with proper hook execution logs
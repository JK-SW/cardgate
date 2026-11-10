#include "card_probe.h"

#include <dlfcn.h>
#include <stddef.h>
#include <string.h>

#include "pkcs11.h"

#define MAX_SLOTS 16

cg_card_probe_result cg_card_probe(const char* module_path)
{
	cg_card_probe_result result = { -1, 0, 0, 0, 0, { 0 } };
	void* module = dlopen(module_path, RTLD_NOW | RTLD_LOCAL);
	if (!module)
		return result;

	CK_C_GetFunctionList get_function_list =
	    (CK_C_GetFunctionList)dlsym(module, "C_GetFunctionList");
	CK_FUNCTION_LIST_PTR p11 = NULL;
	if (!get_function_list || get_function_list(&p11) != CKR_OK || !p11)
		goto unload;

	CK_RV rv = p11->C_Initialize(NULL);
	if (rv != CKR_OK && rv != CKR_CRYPTOKI_ALREADY_INITIALIZED)
	{
		result.error = (long)rv;
		goto unload;
	}

	CK_SLOT_ID slots[MAX_SLOTS];
	CK_ULONG slot_count = MAX_SLOTS;
	rv = p11->C_GetSlotList(CK_TRUE, slots, &slot_count);
	if (rv != CKR_OK)
	{
		result.error = (long)rv;
		goto finalize;
	}

	result.error = 0;
	result.tokens = slot_count;
	if (slot_count > 0)
	{
		CK_TOKEN_INFO info;
		if (p11->C_GetTokenInfo(slots[0], &info) == CKR_OK)
		{
			result.pin_min_length = info.ulMinPinLen;
			result.pin_max_length = info.ulMaxPinLen;
			result.token_flags = info.flags;
		}
		CK_SLOT_INFO slot;
		if (p11->C_GetSlotInfo(slots[0], &slot) == CKR_OK)
		{
			size_t length = sizeof(slot.slotDescription);
			memcpy(result.slot_description, slot.slotDescription, length);
			while (length > 0 && (result.slot_description[length - 1] == ' ' ||
			                      result.slot_description[length - 1] == '\0'))
				length--;
			result.slot_description[length] = '\0';
		}
	}

finalize:
	(void)p11->C_Finalize(NULL);
unload:
	dlclose(module);
	return result;
}

#include "card_probe.h"

#include <dlfcn.h>
#include <stddef.h>

#include "pkcs11.h"

#define MAX_SLOTS 16
#define MAX_OBJECTS 64

cg_card_probe_result cg_card_probe(const char* module_path)
{
	cg_card_probe_result result = { -1, 0, 0, 0, 0, 0 };
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
	for (CK_ULONG i = 0; i < slot_count; i++)
	{
		CK_SESSION_HANDLE session = 0;
		if (p11->C_OpenSession(slots[i], CKF_SERIAL_SESSION, NULL, NULL, &session) != CKR_OK)
			continue;
		CK_OBJECT_CLASS cls = CKO_CERTIFICATE;
		CK_ATTRIBUTE template[] = { { CKA_CLASS, &cls, sizeof(cls) } };
		if (p11->C_FindObjectsInit(session, template, 1) == CKR_OK)
		{
			CK_OBJECT_HANDLE objects[MAX_OBJECTS];
			CK_ULONG found = 0;
			if (p11->C_FindObjects(session, objects, MAX_OBJECTS, &found) == CKR_OK)
			{
				CK_TOKEN_INFO info;
				if (found > 0 && result.certificates == 0 &&
				    p11->C_GetTokenInfo(slots[i], &info) == CKR_OK)
				{
					result.pin_min_length = info.ulMinPinLen;
					result.pin_max_length = info.ulMaxPinLen;
					result.token_flags = info.flags;
				}
				result.certificates += found;
			}
			(void)p11->C_FindObjectsFinal(session);
		}
		(void)p11->C_CloseSession(session);
	}

finalize:
	(void)p11->C_Finalize(NULL);
unload:
	dlclose(module);
	return result;
}

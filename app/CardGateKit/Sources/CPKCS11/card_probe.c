#include "card_probe.h"

#include <dlfcn.h>
#include <stddef.h>
#include <string.h>

#include "pkcs11.h"

#define MAX_SLOTS 16
#define MAX_CERTIFICATES 16
#define MAX_CERTIFICATE_LENGTH 16384

/// Whether the token in the slot holds a certificate the matcher accepts (no login).
static int token_has_certificate(CK_FUNCTION_LIST_PTR p11, CK_SLOT_ID slot, cg_certificate_matcher matches,
                                 void* context)
{
	CK_SESSION_HANDLE session = CK_INVALID_HANDLE;
	if (p11->C_OpenSession(slot, CKF_SERIAL_SESSION, NULL, NULL, &session) != CKR_OK)
		return 0;
	CK_OBJECT_CLASS certificate_class = CKO_CERTIFICATE;
	CK_ATTRIBUTE search[] = { { CKA_CLASS, &certificate_class, sizeof(certificate_class) } };
	CK_OBJECT_HANDLE objects[MAX_CERTIFICATES];
	CK_ULONG count = 0;
	int found = 0;
	if (p11->C_FindObjectsInit(session, search, 1) == CKR_OK)
	{
		if (p11->C_FindObjects(session, objects, MAX_CERTIFICATES, &count) != CKR_OK)
			count = 0;
		(void)p11->C_FindObjectsFinal(session);
	}
	unsigned char value[MAX_CERTIFICATE_LENGTH];
	for (CK_ULONG index = 0; index < count && !found; index++)
	{
		CK_ATTRIBUTE attribute = { CKA_VALUE, value, sizeof(value) };
		if (p11->C_GetAttributeValue(session, objects[index], &attribute, 1) == CKR_OK &&
		    attribute.ulValueLen != CK_UNAVAILABLE_INFORMATION && attribute.ulValueLen <= sizeof(value))
			found = matches(value, attribute.ulValueLen, context) != 0;
	}
	(void)p11->C_CloseSession(session);
	return found;
}

/* Copies a blank padded PKCS#11 text field into a NUL terminated string without the padding. */
static void copy_padded(char* target, const unsigned char* source, size_t length)
{
	memcpy(target, source, length);
	while (length > 0 && (target[length - 1] == ' ' || target[length - 1] == '\0'))
		length--;
	target[length] = '\0';
}

cg_card_probe_result cg_card_probe(const char* module_path)
{
	return cg_card_probe_matching(module_path, NULL, NULL);
}

cg_card_probe_result cg_card_probe_matching(const char* module_path, cg_certificate_matcher matches,
                                            void* context)
{
	cg_card_probe_result result;
	memset(&result, 0, sizeof(result));
	result.error = -1;
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

	CK_INFO library;
	if (p11->C_GetInfo(&library) == CKR_OK)
	{
		copy_padded(result.library_manufacturer, library.manufacturerID, sizeof(library.manufacturerID));
		copy_padded(result.library_description, library.libraryDescription,
		            sizeof(library.libraryDescription));
		result.library_version[0] = library.libraryVersion.major;
		result.library_version[1] = library.libraryVersion.minor;
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
		CK_ULONG chosen = 0;
		if (slot_count > 1 && matches)
		{
			for (CK_ULONG index = 0; index < slot_count; index++)
			{
				if (token_has_certificate(p11, slots[index], matches, context))
				{
					chosen = index;
					result.matched_token = 1;
					break;
				}
			}
		}
		for (CK_ULONG index = 0; index < slot_count; index++)
		{
			CK_TOKEN_INFO info;
			if (p11->C_GetTokenInfo(slots[index], &info) != CKR_OK)
			{
				/* Without the info of the token with the certificate, fall back to all tokens. */
				if (index == chosen)
					result.matched_token = 0;
				continue;
			}
			result.any_token_flags |= info.flags;
			if (index == chosen)
			{
				result.pin_min_length = info.ulMinPinLen;
				result.pin_max_length = info.ulMaxPinLen;
				result.token_flags = info.flags;
				copy_padded(result.token_manufacturer, info.manufacturerID, sizeof(info.manufacturerID));
				copy_padded(result.token_model, info.model, sizeof(info.model));
				result.token_hardware_version[0] = info.hardwareVersion.major;
				result.token_hardware_version[1] = info.hardwareVersion.minor;
				result.token_firmware_version[0] = info.firmwareVersion.major;
				result.token_firmware_version[1] = info.firmwareVersion.minor;
			}
		}
		CK_SLOT_INFO slot;
		if (p11->C_GetSlotInfo(slots[0], &slot) == CKR_OK)
		{
			copy_padded(result.slot_description, slot.slotDescription, sizeof(slot.slotDescription));
		}
	}

finalize:
	(void)p11->C_Finalize(NULL);
unload:
	dlclose(module);
	return result;
}

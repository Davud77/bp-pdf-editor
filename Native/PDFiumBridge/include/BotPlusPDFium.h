// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 BotPlus

#ifndef BOTPLUS_PDFIUM_H
#define BOTPLUS_PDFIUM_H
#include <stddef.h>
#include "fpdfview.h"
#include "fpdf_edit.h"
#include "fpdf_text.h"
#include "fpdf_annot.h"
#include "fpdf_save.h"
#include "fpdf_ppo.h"
#include "fpdf_attachment.h"
#include "fpdf_doc.h"
#include "fpdf_transformpage.h"
#ifdef __cplusplus
extern "C" {
#endif
unsigned char* BotPlusPDFium_SaveDocument(FPDF_DOCUMENT document, size_t* length);
void BotPlusPDFium_Free(void* memory);
#ifdef __cplusplus
}
#endif
#endif

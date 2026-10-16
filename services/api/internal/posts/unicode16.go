package posts

// Unicode 16.0 属性摘录；冻结版本，避免 Go 工具链 Unicode 版本影响判定。
// Copyright © 1991-2024 Unicode, Inc. 数据许可：https://www.unicode.org/license.txt
// 数据来源：https://www.unicode.org/Public/16.0.0/ucd/

// PropList.txt SHA-256: 53d614508e2a0b2305a8aa21cd60d993de9326cdf65993660dfcce4503548583
func unicode16WhiteSpace(scalar rune) bool {
	switch {
	case scalar >= 0x9 && scalar <= 0xd:
		return true
	case scalar == 0x20:
		return true
	case scalar == 0x85:
		return true
	case scalar == 0xa0:
		return true
	case scalar == 0x1680:
		return true
	case scalar >= 0x2000 && scalar <= 0x200a:
		return true
	case scalar == 0x2028:
		return true
	case scalar == 0x2029:
		return true
	case scalar == 0x202f:
		return true
	case scalar == 0x205f:
		return true
	case scalar == 0x3000:
		return true
	}
	return false
}

// DerivedCoreProperties.txt SHA-256: 39d35161f2954497f69e08bdb9e701493f476a3d30222de20028feda36c1dabd
func unicode16DefaultIgnorable(scalar rune) bool {
	switch {
	case scalar == 0xad:
		return true
	case scalar == 0x34f:
		return true
	case scalar == 0x61c:
		return true
	case scalar >= 0x115f && scalar <= 0x1160:
		return true
	case scalar >= 0x17b4 && scalar <= 0x17b5:
		return true
	case scalar >= 0x180b && scalar <= 0x180d:
		return true
	case scalar == 0x180e:
		return true
	case scalar == 0x180f:
		return true
	case scalar >= 0x200b && scalar <= 0x200f:
		return true
	case scalar >= 0x202a && scalar <= 0x202e:
		return true
	case scalar >= 0x2060 && scalar <= 0x2064:
		return true
	case scalar == 0x2065:
		return true
	case scalar >= 0x2066 && scalar <= 0x206f:
		return true
	case scalar == 0x3164:
		return true
	case scalar >= 0xfe00 && scalar <= 0xfe0f:
		return true
	case scalar == 0xfeff:
		return true
	case scalar == 0xffa0:
		return true
	case scalar >= 0xfff0 && scalar <= 0xfff8:
		return true
	case scalar >= 0x1bca0 && scalar <= 0x1bca3:
		return true
	case scalar >= 0x1d173 && scalar <= 0x1d17a:
		return true
	case scalar == 0xe0000:
		return true
	case scalar == 0xe0001:
		return true
	case scalar >= 0xe0002 && scalar <= 0xe001f:
		return true
	case scalar >= 0xe0020 && scalar <= 0xe007f:
		return true
	case scalar >= 0xe0080 && scalar <= 0xe00ff:
		return true
	case scalar >= 0xe0100 && scalar <= 0xe01ef:
		return true
	case scalar >= 0xe01f0 && scalar <= 0xe0fff:
		return true
	}
	return false
}

package names

// NaturalLess compares two strings case/accent-insensitively with digit runs
// compared numerically ("Bölüm 2" < "Bölüm 10").
func NaturalLess(a, b string) bool {
	return NaturalCompareKeys(sortFold(a), sortFold(b)) < 0
}

// NaturalLessKey compares keys produced by SortKey.
func NaturalLessKey(a, b string) bool { return NaturalCompareKeys(a, b) < 0 }

func isDigit(c byte) bool { return c >= '0' && c <= '9' }

// NaturalCompareKeys compares already-folded strings naturally.
func NaturalCompareKeys(a, b string) int {
	i, j := 0, 0
	for i < len(a) && j < len(b) {
		ca, cb := a[i], b[j]
		if isDigit(ca) && isDigit(cb) {
			si := i
			for i < len(a) && isDigit(a[i]) {
				i++
			}
			sj := j
			for j < len(b) && isDigit(b[j]) {
				j++
			}
			na, nb := trimZeros(a[si:i]), trimZeros(b[sj:j])
			if len(na) != len(nb) {
				if len(na) < len(nb) {
					return -1
				}
				return 1
			}
			if na != nb {
				if na < nb {
					return -1
				}
				return 1
			}
			// equal value: fewer leading zeros first
			if (i - si) != (j - sj) {
				if (i - si) < (j - sj) {
					return -1
				}
				return 1
			}
			continue
		}
		if ca != cb {
			if ca < cb {
				return -1
			}
			return 1
		}
		i++
		j++
	}
	switch {
	case len(a)-i < len(b)-j:
		return -1
	case len(a)-i > len(b)-j:
		return 1
	}
	return 0
}

func trimZeros(s string) string {
	for len(s) > 1 && s[0] == '0' {
		s = s[1:]
	}
	return s
}

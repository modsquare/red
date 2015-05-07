Red/System [
	Title:   "Tuple! datatype runtime functions"
	Author:  "Qingtian Xie"
	File: 	 %tuple.reds
	Tabs:	 4
	Rights:  "Copyright (C) 2011-2012 Nenad Rakocevic. All rights reserved."
	License: {
		Distributed under the Boost Software License, Version 1.0.
		See https://github.com/dockimbel/Red/blob/master/BSL-License.txt
	}
]

tuple: context [
	verbose: 0

	make-in: func [
		parent	[red-block!]
		bs1		[integer!]								;-- pre-encoded in little-endian
		bs2		[integer!]								;-- pre-encoded in little-endian
		bs3		[integer!]								;-- pre-encoded in little-endian
		return: [red-tuple!]
		/local
			ts	 [red-tuple!]
			bits [int-ptr!]
	][
		ts: as red-tuple! ALLOC_TAIL(parent)
		ts/header: TYPE_TUPLE							;-- implicit reset of all header flags
		
		bits: as int-ptr! ts
		bits/2: bs1
		bits/3: bs2
		bits/4: bs3
		ts
	]

	push: func [
		str		[c-string!]
		return: [red-tuple!]
		/local
			tp	 [red-tuple!]
			size [integer!]
			p	 [byte-ptr!]
			c	 [integer!]
			n	 [integer!]
			m	 [integer!]
	][
		#if debug? = yes [if verbose > 0 [print-line "tuple/push"]]
		
		tp: as red-tuple! stack/push*
		tp/header: TYPE_TUPLE
		size: 1
		p: (as byte-ptr! tp) + 4

		n: 0
		while [
			c: as-integer str/1
			c <> 0
		][
			either c = as-integer #"." [
				size: size + 1
				p/size: as byte! n
				n: 0
			][
				m: n * 10
				n: m
				m: n + c - #"0"
				n: m
			]
			str: str + 1
		]
		p/1: as byte! size
		size: size + 1									;-- last number
		p/size: as byte! n
		tp
	]

	do-math: func [
		type	  [integer!]
		return:	  [red-tuple!]
		/local
			left  [red-tuple!]
			right [red-tuple!]
			int   [red-integer!]
			fl    [red-float!]
			tp1   [byte-ptr!]
			tp2   [byte-ptr!]
			size  [integer!]
			size1 [integer!]
			size2 [integer!]
			v	  [integer!]
			v1	  [integer!]
			n	  [integer!]
	][
		#if debug? = yes [if verbose > 0 [print-line "float/do-math"]]

		left:  as red-tuple! stack/arguments
		right: as red-tuple! left + 1

		size2: 0
		switch TYPE_OF(right) [
			TYPE_TUPLE [
				tp2: (as byte-ptr! right) + 4
				size2: as-integer tp2/1
				tp2: tp2 + 1
			]
			TYPE_INTEGER [
				int: as red-integer! right
				v: int/value
			]
			TYPE_FLOAT
			TYPE_PERCENT [
				fl: as red-float! right
				v: float/to-integer fl/value
			]
			default [
				fire [TO_ERROR(script invalid-type) datatype/push TYPE_OF(right)]
			]
		]

		tp1: (as byte-ptr! left) + 4
		size1: as-integer tp1/1
		size: either size1 < size2 [
			tp1/1: as byte! size2
			size2
		][size1]
		tp1: tp1 + 1
		n: 0
		until [
			n: n + 1
			if positive? size2 [
				v: either n <= size2 [as-integer tp2/n][0]
			]
			v1: either n <= size1 [as-integer tp1/n][0]
			v1: switch type [
				OP_ADD [v1 + v]
				OP_SUB [v1 - v]
				OP_MUL [v1 * v]
				OP_AND [v1 and v]
				OP_OR  [v1 or v]
				OP_XOR [v1 xor v]
				OP_REM [
					either zero? v [
						fire [TO_ERROR(math zero-divide)]
						0								;-- pass the compiler's type-checking
					][v1 % v]
				]
				OP_DIV [
					either zero? v [
						fire [TO_ERROR(math zero-divide)]
						0								;-- pass the compiler's type-checking
					][v1 / v]
				]
			]
			either v1 > 255 [v1: 255][if negative? v1 [v1: 0]]
			tp1/n: as byte! v1
			n = size
		]
		left
	]

	;-- Actions --

	make: func [
		proto	 [red-value!]	
		spec	 [red-value!]
		return:	 [red-tuple!]
		/local
			blk   [red-block!]
			tuple [red-tuple!]
			tp    [byte-ptr!]
			n	  [integer!]
			i	  [integer!]
			s	  [series!]
			int   [red-integer!]
	][
		#if debug? = yes [if verbose > 0 [print-line "tuple/make"]]

		switch TYPE_OF(spec) [
			TYPE_TUPLE [
				as red-tuple! spec
			]
			TYPE_BLOCK [
				blk: as red-block! spec
				tuple: as red-tuple! stack/push*
				tuple/header: TYPE_TUPLE
				tp: (as byte-ptr! tuple) + 4
				n: block/rs-length? blk
				if n > 10 [
					fire [TO_ERROR(script bad-make-arg) proto spec]
				]
				tp/1: as byte! either n > 2 [n][3]
				tp: tp + 1
				s: GET_BUFFER(blk)
				int: as red-integer! s/offset + blk/head
				i: 0
				while [i < n][
					i: i + 1
					if any [
						int/value > 255
						int/value < 0
					][fire [TO_ERROR(script bad-make-arg) proto spec]]
					tp/i: as byte! int/value
					int: int + 1
				]
				while [i < 3][i: i + 1 tp/i: null-byte]
				tuple
			]
			default [
				fire [TO_ERROR(script bad-make-arg) proto spec]
				null
			]
		]
	]

	form: func [
		tp		   [red-tuple!]
		buffer	   [red-string!]
		arg		   [red-value!]
		part 	   [integer!]
		return:    [integer!]
		/local
			formed [c-string!]
			value  [byte-ptr!]
			n	   [integer!]
			size   [integer!]
	][
		#if debug? = yes [if verbose > 0 [print-line "tuple/form"]]

		value: (as byte-ptr! tp) + 4
		size: as-integer value/1
		value: value + 1
		n: 1
		until [
			formed: integer/form-signed as-integer value/n
			string/concatenate-literal buffer formed
			unless n = size [
				part: part - 1
				string/append-char GET_BUFFER(buffer) as-integer #"."
			]
			part: part - system/words/length? formed	;@@ optimize by removing length?
			n: n + 1
			n > size
		]
		part
	]

	mold: func [
		tp		[red-tuple!]
		buffer	[red-string!]
		only?	[logic!]
		all?	[logic!]
		flat?	[logic!]
		arg		[red-value!]
		part 	[integer!]
		indent	[integer!]		
		return: [integer!]
	][
		#if debug? = yes [if verbose > 0 [print-line "tuple/mold"]]

		form tp buffer arg part
	]

	eval-path: func [
		parent	[red-tuple!]							;-- implicit type casting
		element	[red-value!]
		value	[red-value!]
		return:	[red-value!]
		/local
			int  [red-integer!]
			type [integer!]
	][
		type: TYPE_OF(element)
		either type = TYPE_INTEGER [
			int: as red-integer! element
			either value <> null [
				poke parent int/value value null
				value
			][
				pick parent int/value null
			]
		][
			fire [TO_ERROR(script invalid-type) datatype/push TYPE_OF(element)]
			null
		]
	]

	compare: func [
		tp1		[red-tuple!]							;-- first operand
		tp2		[red-tuple!]							;-- second operand
		op		[integer!]								;-- type of comparison
		return: [integer!]
		/local
			p1	 [byte-ptr!]
			p2	 [byte-ptr!]
			i	 [integer!]
			sz   [integer!]
			sz1  [integer!]
			sz2  [integer!]
			v1	 [integer!]
			v2	 [integer!]
	][
		#if debug? = yes [if verbose > 0 [print-line "tuple/compare"]]

		if TYPE_OF(tp2) <> TYPE_TUPLE [RETURN_COMPARE_OTHER]
		p1: (as byte-ptr! tp1) + 4
		p2: (as byte-ptr! tp2) + 4
		sz1: as-integer p1/1
		sz2: as-integer p2/1
		sz: either sz1 > sz2 [sz1][sz2]
		p1: p1 + 1
		p2: p2 + 1

		i: 0
		until [
			i: i + 1
			v1: either i > sz1 [0][as-integer p1/i] 
			v2: either i > sz2 [0][as-integer p2/i]
			if v1 <> v2 [return SIGN_COMPARE_RESULT(v1 v2)]
			i = sz
		]
		0
	]

	add: func [return: [red-value!]][
		#if debug? = yes [if verbose > 0 [print-line "tuple/add"]]
		as red-value! do-math OP_ADD
	]

	divide: func [return: [red-value!]][
		#if debug? = yes [if verbose > 0 [print-line "tuple/divide"]]
		as red-value! do-math OP_DIV
	]

	multiply: func [return:	[red-value!]][
		#if debug? = yes [if verbose > 0 [print-line "tuple/multiply"]]
		as red-value! do-math OP_MUL
	]

	subtract: func [return:	[red-value!]][
		#if debug? = yes [if verbose > 0 [print-line "tuple/subtract"]]
		as red-value! do-math OP_SUB
	]

	remainder: func [return: [red-value!]][
		#if debug? = yes [if verbose > 0 [print-line "tuple/remainder"]]
		as red-value! do-math OP_REM
	]

	and~: func [return:	[red-value!]][
		#if debug? = yes [if verbose > 0 [print-line "tuple/and~"]]
		as red-value! do-math OP_AND
	]

	or~: func [return: [red-value!]][
		#if debug? = yes [if verbose > 0 [print-line "tuple/or~"]]
		as red-value! do-math OP_OR
	]

	xor~: func [return:	[red-value!]][
		#if debug? = yes [if verbose > 0 [print-line "tuple/xor~"]]
		as red-value! do-math OP_XOR
	]

	length?: func [
		tp		[red-tuple!]
		return: [integer!]
		/local
			value  [byte-ptr!]
	][
		#if debug? = yes [if verbose > 0 [print-line "tuple/length?"]]

		value: (as byte-ptr! tp) + 4
		as-integer value/1
	]

	pick: func [
		tp		[red-tuple!]
		index	[integer!]
		boxed	[red-value!]
		return:	[red-value!]
		/local
			value	[byte-ptr!]
			size	[integer!]
	][
		#if debug? = yes [if verbose > 0 [print-line "tuple/pick"]]

		value: (as byte-ptr! tp) + 4
		size: as-integer value/1
		value: value + 1

		either any [
			index <= 0
			index > size
		][
			none-value
		][
			as red-value! integer/box as-integer value/index
		]
	]

	poke: func [
		tp		[red-tuple!]
		index	[integer!]
		data	[red-value!]
		boxed	[red-value!]
		return:	[red-value!]
		/local
			value [byte-ptr!]
			size  [integer!]
			int   [red-integer!]
			v	  [integer!]
	][
		#if debug? = yes [if verbose > 0 [print-line "tuple/poke"]]

		value: (as byte-ptr! tp) + 4
		size: as-integer value/1
		value: value + 1

		either any [
			index <= 0
			index > size
		][
			fire [TO_ERROR(script out-of-range) boxed]
		][
			int: as red-integer! data
			v: int/value
			either v > 255 [v: 255][if negative? v [v: 0]]
			value/index: as byte! v
		]
		as red-value! data
	]

	reverse: func [
		tuple	 [red-tuple!]
		part-arg [red-value!]
		return:	 [red-value!]
		/local
			int  [red-integer!]
			part [integer!]
			tmp  [byte!]
			size [integer!]
			n	 [integer!]
			m	 [integer!]
			tp   [byte-ptr!]
	][
		#if debug? = yes [if verbose > 0 [print-line "tuple/reverse"]]

		tp: (as byte-ptr! tuple) + 4
		size: as-integer tp/1
		part: size
		if OPTION?(part-arg) [
			either TYPE_OF(part-arg) = TYPE_INTEGER [
				int: as red-integer! part-arg
				part: int/value
				if negative? part [
					fire [TO_ERROR(script out-of-range) int]
				]
			][
				ERR_INVALID_REFINEMENT_ARG(refinements/_part part-arg)
			]
		]

		tp: tp + 1
		if part < size [size: part]
		n: 1
		while [n < size] [
			tmp: tp/n
			tp/n: tp/size
			tp/size: tmp
			n: n + 1
			size: size - 1
		]
		as red-value! tuple
	]

	init: does [
		datatype/register [
			TYPE_TUPLE
			TYPE_VALUE
			"tuple!"
			;-- General actions --
			:make
			null			;random
			null			;reflect
			null			;to
			:form
			:mold
			:eval-path
			null			;set-path
			:compare
			;-- Scalar actions --
			null			;absolute
			:add
			:divide
			:multiply
			null			;negate
			null			;power
			:remainder
			null			;round
			:subtract
			null			;even?
			null			;odd?
			;-- Bitwise actions --
			:and~
			null			;complement
			:or~
			:xor~
			;-- Series actions --
			null			;append
			null			;at
			null			;back
			null			;change
			null			;clear
			null			;copy
			null			;find
			null			;head
			null			;head?
			null			;index?
			null			;insert
			:length?
			null			;next
			:pick
			:poke
			null			;remove
			:reverse
			null			;select
			null			;sort
			null			;skip
			null			;swap
			null			;tail
			null			;tail?
			null			;take
			null			;trim
			;-- I/O actions --
			null			;create
			null			;close
			null			;delete
			null			;modify
			null			;open
			null			;open?
			null			;query
			null			;read
			null			;rename
			null			;update
			null			;write
		]
	]
]
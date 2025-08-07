const std = @import("std");

pub const Errno = error{
    E2BIG,
    EACCES,
    EADDRINUSE,
    EADDRNOTAVAIL,
    EAFNOSUPPORT,
    EAGAIN,
    EALREADY,
    EBADF,
    EBADMSG,
    EBUSY,
    ECANCELED,
    ECHILD,
    ECONNABORTED,
    ECONNREFUSED,
    ECONNRESET,
    EDEADLK,
    EDESTADDRREQ,
    EDOM,
    EDQUOT,
    EEXIST,
    EFAULT,
    EFBIG,
    EHOSTUNREACH,
    EIDRM,
    EILSEQ,
    EINPROGRESS,
    EINTR,
    EINVAL,
    EIO,
    EISCONN,
    EISDIR,
    ELOOP,
    EMFILE,
    EMLINK,
    EMSGSIZE,
    EMULTIHOP,
    ENAMETOOLONG,
    ENETDOWN,
    ENETRESET,
    ENETUNREACH,
    ENFILE,
    ENOBUFS,
    ENODATA,
    ENODEV,
    ENOENT,
    ENOEXEC,
    ENOLCK,
    ENOLINK,
    ENOMEM,
    ENOMSG,
    ENOPROTOOPT,
    ENOSPC,
    ENOSR,
    ENOSTR,
    ENOSYS,
    ENOTCONN,
    ENOTDIR,
    ENOTEMPTY,
    ENOTRECOVERABLE,
    ENOTSOCK,
    ENOTSUP,
    ENOTTY,
    ENXIO,
    EOPNOTSUPP,
    EOVERFLOW,
    EOWNERDEAD,
    EPERM,
    EPIPE,
    EPROTO,
    EPROTONOSUPPORT,
    EPROTOTYPE,
    ERANGE,
    EROFS,
    ESPIPE,
    ESRCH,
    ESTALE,
    ETIME,
    ETIMEDOUT,
    ETXTBSY,
    EWOULDBLOCK,
    EXDEV,
};

pub fn is_in_set(e: anytype, comptime s: type) bool {
    @setEvalBranchQuota(10_000);
    return switch (e) {
        inline else => |ce| comptime b: {
            const errors = @typeInfo(s).error_set orelse return false;
            for (errors) |err| {
                if (std.mem.eql(u8, err.name, @errorName(ce))) break :b true;
            }
            break :b false;
        },
    };
}

pub fn error_num(e: Errno) usize {
    @setEvalBranchQuota(10_000);
    return switch (e) {
        inline else => |ce| comptime b: {
            const errors = @typeInfo(Errno).error_set orelse unreachable;
            for (errors, 1..) |err, n| {
                if (std.mem.eql(u8, err.name, @errorName(ce))) break :b n;
            }
            unreachable;
        },
    };
}
